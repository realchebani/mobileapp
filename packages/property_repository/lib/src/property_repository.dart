import 'dart:math';
import 'dart:typed_data';

import 'package:property_repository/property_repository.dart';
import 'package:property_repository/src/models/json.dart';
import 'package:supabase/supabase.dart';

/// {@template property_failure}
/// Base class of the failures thrown by [PropertyRepository].
/// {@endtemplate}
sealed class PropertyFailure implements Exception {
  /// {@macro property_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  String get _name;

  @override
  String toString() => '$_name($error)';
}

/// Thrown when a property does not exist or is not visible to the user.
final class PropertyNotFoundFailure extends PropertyFailure {
  const new(this.propertyId);

  /// Identifier of the missing property.
  final String propertyId;

  @override
  String get _name => 'PropertyNotFoundFailure';

  @override
  String toString() => '$_name($propertyId)';
}

/// Thrown when reading a property, its children or a document URL fails.
final class PropertyLoadFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'PropertyLoadFailure';
}

/// Thrown when creating or updating a property or one of its children
/// fails.
final class PropertySaveFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'PropertySaveFailure';
}

/// Thrown when deleting a child row or a document fails.
final class PropertyDeleteFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'PropertyDeleteFailure';
}

/// Thrown when uploading a document file fails.
final class DocumentUploadFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'DocumentUploadFailure';
}

/// Thrown when asking the backend for the non-certified estimate fails.
final class EstimateRequestFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'EstimateRequestFailure';
}

/// Thrown when the user asked for too many estimates (3 new computations
/// per 24 h, a cost cap of the backend).
final class EstimateRateLimitFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'EstimateRateLimitFailure';
}

/// Thrown when creating a property would exceed
/// [PropertyRepository.maxProperties] (test phase limit).
final class PropertyLimitFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'PropertyLimitFailure';
}

/// Thrown when a sale lot cannot change because one of its properties is
/// reviewed by the expert or certified (the lot is frozen).
final class LotFrozenFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'LotFrozenFailure';
}

/// Thrown when a room already has 12 photos, or the property 150
/// (EPIC-15, enforced by the database).
final class RoomPhotoLimitFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'RoomPhotoLimitFailure';
}

/// Thrown when deleting the last photo of a main room of a submitted
/// dossier (enforced by the database: the dossier was sent with it).
final class RoomPhotoRequiredFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'RoomPhotoRequiredFailure';
}

/// Thrown when the daily quota of the vision AI is used up (HTTP 429).
final class VisionQuotaFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'VisionQuotaFailure';
}

/// Thrown when the same photo or plan is already being analysed by
/// another request (HTTP 409 `busy`): try again in a moment.
final class VisionBusyFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'VisionBusyFailure';
}

/// Thrown when the vision AI cannot answer (analysis of a photo, reading
/// of a plan).
final class VisionRequestFailure extends PropertyFailure {
  const new([super.error]);

  @override
  String get _name => 'VisionRequestFailure';
}

/// {@template property_repository}
/// Reads and writes seller dossiers: the `properties` table, its child
/// tables and the private `property-documents` Storage bucket.
///
/// Row level security only lets a signed-in user access their own
/// properties (and the files under their own `<user id>/` folder).
/// {@endtemplate}
class PropertyRepository {
  /// {@macro property_repository}
  new({required this._client, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SupabaseClient _client;
  final DateTime Function() _now;

  static const _properties = 'properties';

  /// Storage bucket of the documents.
  static const documentsBucket = 'property-documents';

  // ---------------------------------------------------------------------
  // Properties.
  // ---------------------------------------------------------------------

  /// Most properties a user may have (test phase, enforced by the
  /// database).
  static const maxProperties = 5;

  static const _uniqueViolation = '23505';

  /// Every property of [ownerId], oldest first.
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<List<Property>> listProperties(String ownerId) async {
    try {
      final rows = await _client
          .from(_properties)
          .select()
          .eq(PropertyColumns.ownerId, ownerId)
          .order(PropertyColumns.createdAt, ascending: true);
      return [for (final row in rows) Property.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  /// Creates the draft [id] of [ownerId] (the app chooses the id, e.g.
  /// with [generateUuidV4]) with its [type] and [lotId] if known, and
  /// returns it.
  ///
  /// Retry-safe: when the property was already created (an earlier answer
  /// was lost), it is returned as is.
  ///
  /// Throws [PropertyLimitFailure] when the user already has
  /// [maxProperties] properties, [LotFrozenFailure] when the lot is frozen
  /// and [PropertySaveFailure] on any other error.
  Future<Property> createProperty({
    required String id,
    required String ownerId,
    PropertyType? type,
    String? typeOther,
    String? lotId,
  }) async {
    try {
      final row = await _client
          .from(_properties)
          .insert({
            PropertyColumns.id: id,
            PropertyColumns.ownerId: ownerId,
            PropertyColumns.propertyType: ?type?.value,
            PropertyColumns.propertyTypeOther: ?typeOther,
            PropertyColumns.lotId: ?lotId,
          })
          .select()
          .single();
      return Property.fromJson(row);
    } on PostgrestException catch (error, stackTrace) {
      if (error.code == _uniqueViolation) {
        try {
          return await getProperty(id);
        } on PropertyFailure {
          // Not the user's property: report the original error.
        }
      }
      Error.throwWithStackTrace(_saveFailure(error), stackTrace);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Maps the errors raised by the database rules (limit, frozen lot).
  static PropertyFailure _saveFailure(Object error) {
    if (error is PostgrestException) {
      if (error.message == 'property_limit_reached') {
        return PropertyLimitFailure(error);
      }
      if (error.message == 'lot_frozen') return LotFrozenFailure(error);
    }
    return PropertySaveFailure(error);
  }

  /// Files listed per page when deleting a property (the storage
  /// default).
  static const _filesPage = 100;

  /// Deletes the draft [property]: its document files first (the storage
  /// rules need the property to still exist), then the property, whose
  /// child rows go with it. The status is read again first: the files of a
  /// dossier sent meanwhile are never deleted.
  ///
  /// Throws [PropertyDeleteFailure] when the property is not a draft (or
  /// belongs to a frozen lot) or on error.
  Future<void> deleteProperty(Property property) async {
    try {
      final current = await getProperty(property.id);
      if (current.status != PropertyStatus.draft) {
        throw PropertyDeleteFailure('${property.id} is not a draft');
      }
      final folder = '${property.ownerId}/${property.id}';
      final bucket = _client.storage.from(documentsBucket);
      final paths = <String>[];
      for (var offset = 0; ; offset += _filesPage) {
        final files = await bucket.list(
          path: folder,
          searchOptions: SearchOptions(offset: offset),
        );
        paths.addAll([for (final file in files) '$folder/${file.name}']);
        if (files.length < _filesPage) break;
      }
      // The room photos live in sub-folders, which list() does not walk.
      final photos = await _client
          .from(_roomPhotos)
          .select('storage_path')
          .eq('property_id', property.id);
      paths.addAll([for (final row in photos) row['storage_path']! as String]);
      for (var start = 0; start < paths.length; start += _filesPage) {
        await bucket.remove(
          paths.sublist(start, min(start + _filesPage, paths.length)),
        );
      }
      final deleted = await _client
          .from(_properties)
          .delete()
          .eq(PropertyColumns.id, property.id)
          .select(PropertyColumns.id);
      if (deleted.isEmpty) {
        throw PropertyDeleteFailure('${property.id} was not deleted');
      }
    } on PropertyDeleteFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyDeleteFailure(error), stackTrace);
    }
  }

  /// Returns the property [id].
  ///
  /// Throws [PropertyNotFoundFailure] when there is no such property and
  /// [PropertyLoadFailure] on any other error.
  Future<Property> getProperty(String id) async {
    final Map<String, dynamic>? row;
    try {
      row = await _client
          .from(_properties)
          .select()
          .eq(PropertyColumns.id, id)
          .maybeSingle();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
    if (row == null) throw PropertyNotFoundFailure(id);
    return Property.fromJson(row);
  }

  /// Updates the columns of [patch] (keys from [PropertyColumns]) on the
  /// property [id] and returns the updated property.
  ///
  /// Values may be Dart enums, lists of them and [DateTime]s: they are
  /// encoded as stored. Only send the columns that change (not
  /// [Property.toJson], which also holds columns the app may not write).
  /// The `provenance` column is replaced as a whole: build it with
  /// [Property.mergeProvenance] to keep the other entries.
  ///
  /// Throws [PropertyNotFoundFailure] when no property was updated and
  /// [PropertySaveFailure] on any other error.
  Future<Property> updateProperty(String id, Map<String, Object?> patch) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client
          .from(_properties)
          .update(encodeDbValue(patch)! as Map<String, Object?>)
          .eq(PropertyColumns.id, id)
          .select();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
    if (rows.isEmpty) throw PropertyNotFoundFailure(id);
    return Property.fromJson(rows.single);
  }

  // ---------------------------------------------------------------------
  // Child collections.
  // ---------------------------------------------------------------------

  /// Owners of [propertyId], by position.
  Future<List<PropertyOwner>> getOwners(String propertyId) =>
      _list(_owners, propertyId);

  /// Inserts or updates (by id) [owner]; returns the saved row.
  Future<PropertyOwner> saveOwner(PropertyOwner owner) =>
      _save(_owners, owner.toJson());

  /// Deletes the owner [id].
  Future<void> deleteOwner(String id) => _delete(_owners, id);

  /// Copies the owners of [fromPropertyId] to [toPropertyId] (new rows,
  /// same positions, the user's profile link kept) and returns the copies.
  ///
  /// Retry-safe: rows are matched by position, so copying again updates
  /// them instead of adding duplicates.
  ///
  /// Throws [PropertyLoadFailure] or [PropertySaveFailure] on error.
  Future<List<PropertyOwner>> copyOwners({
    required String fromPropertyId,
    required String toPropertyId,
  }) async {
    final owners = await getOwners(fromPropertyId);
    if (owners.isEmpty) return const [];
    try {
      final rows = await _client
          .from(_owners.name)
          .upsert([
            for (final owner in owners)
              {...owner.toJson()..remove('id'), 'property_id': toPropertyId},
          ], onConflict: 'property_id,position')
          .select()
          .order('position', ascending: true);
      return [for (final row in rows) PropertyOwner.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Cadastral parcels of [propertyId].
  Future<List<PropertyParcel>> getParcels(String propertyId) =>
      _list(_parcels, propertyId);

  /// Inserts or updates [parcel], matched by its cadastre identifier within
  /// the property (`property_id`, `idu`), so that saving again a parcel
  /// whose insert answer was lost does not fail; returns the saved row.
  Future<PropertyParcel> saveParcel(PropertyParcel parcel) =>
      _save(_parcels, parcel.toJson(), onConflict: 'property_id,idu');

  /// Deletes the parcel [id].
  Future<void> deleteParcel(String id) => _delete(_parcels, id);

  /// Previous agency estimates of [propertyId].
  Future<List<PreviousEstimate>> getPreviousEstimates(String propertyId) =>
      _list(_estimates, propertyId);

  /// Inserts or updates (by id) [estimate]; returns the saved row.
  Future<PreviousEstimate> savePreviousEstimate(PreviousEstimate estimate) =>
      _save(_estimates, estimate.toJson());

  /// Deletes the estimate [id].
  Future<void> deletePreviousEstimate(String id) => _delete(_estimates, id);

  /// Rooms of [propertyId], by sort order.
  Future<List<Room>> getRooms(String propertyId) => _list(_rooms, propertyId);

  /// Inserts or updates (by id) [room]; returns the saved row.
  Future<Room> saveRoom(Room room) => _save(_rooms, room.toJson());

  /// Deletes the room [id].
  Future<void> deleteRoom(String id) => _delete(_rooms, id);

  /// Assets and watch points of [propertyId], by sort order.
  Future<List<LifestyleItem>> getLifestyleItems(String propertyId) =>
      _list(_lifestyleItems, propertyId);

  /// Inserts or updates (by id) [item]; returns the saved row.
  Future<LifestyleItem> saveLifestyleItem(LifestyleItem item) =>
      _save(_lifestyleItems, item.toJson());

  /// Deletes the lifestyle item [id].
  Future<void> deleteLifestyleItem(String id) => _delete(_lifestyleItems, id);

  /// The open pending answers of [propertyId] (EPIC-16: values said on
  /// another step, pre-filled « À confirmer »), oldest first.
  Future<List<PendingAnswer>> getPendingAnswers(String propertyId) async {
    try {
      final rows = await _client
          .from('pending_answers')
          .select()
          .eq('property_id', propertyId)
          .eq('status', PendingStatus.pending.value)
          .order('created_at', ascending: true);
      return [for (final row in rows) PendingAnswer.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  /// Closes the pending answers [ids] with [resolution] (its status). Only
  /// open ones change: resolving twice (a retry, another device) is a
  /// no-op. Returns the ids actually resolved.
  Future<List<String>> resolvePendingAnswers(
    List<String> ids,
    PendingResolution resolution,
  ) async {
    if (ids.isEmpty) return const [];
    try {
      final rows = await _client
          .from('pending_answers')
          .update({
            'status': resolution.status.value,
            'resolution': resolution.value,
          })
          .inFilter('id', ids)
          .eq('status', PendingStatus.pending.value)
          .select('id');
      return [for (final row in rows) row['id'] as String];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Documents of [propertyId], oldest first.
  Future<List<PropertyDocument>> getDocuments(String propertyId) =>
      _list(_documents, propertyId);

  /// Documents of every property of [propertyIds] (the vault, EPIC-11),
  /// oldest first.
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<List<PropertyDocument>> getDocumentsOf(
    List<String> propertyIds,
  ) async {
    if (propertyIds.isEmpty) return const [];
    try {
      final rows = await _client
          .from(_documents.name)
          .select()
          .inFilter('property_id', propertyIds)
          .order(_documents.orderBy, ascending: true)
          .order('created_at', ascending: true);
      return [for (final row in rows) PropertyDocument.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  static const _Table<PropertyOwner> _owners = _Table(
    'property_owners',
    'position',
    PropertyOwner.fromJson,
  );
  static const _Table<PropertyParcel> _parcels = _Table(
    'property_parcels',
    'created_at',
    PropertyParcel.fromJson,
  );
  static const _Table<PreviousEstimate> _estimates = _Table(
    'previous_estimates',
    'created_at',
    PreviousEstimate.fromJson,
  );
  static const _Table<Room> _rooms = _Table(
    'rooms',
    'sort_order',
    Room.fromJson,
  );
  static const _Table<LifestyleItem> _lifestyleItems = _Table(
    'lifestyle_items',
    'sort_order',
    LifestyleItem.fromJson,
  );
  static const _Table<PropertyDocument> _documents = _Table(
    'property_documents',
    'uploaded_at',
    PropertyDocument.fromJson,
  );

  Future<List<T>> _list<T>(_Table<T> table, String propertyId) async {
    try {
      final rows = await _client
          .from(table.name)
          .select()
          .eq('property_id', propertyId)
          .order(table.orderBy, ascending: true)
          .order('created_at', ascending: true);
      return [for (final row in rows) table.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  Future<T> _save<T>(
    _Table<T> table,
    Map<String, Object?> row, {
    String? onConflict,
  }) async {
    try {
      final saved = await _client
          .from(table.name)
          .upsert(row, onConflict: onConflict)
          .select()
          .single();
      return table.fromJson(saved);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  Future<void> _delete<T>(_Table<T> table, String id) async {
    try {
      await _client.from(table.name).delete().eq('id', id);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyDeleteFailure(error), stackTrace);
    }
  }

  // ---------------------------------------------------------------------
  // Documents (Storage).
  // ---------------------------------------------------------------------

  /// Uploads [bytes] as a document of [kind] of the property [propertyId]
  /// (owned by [ownerId]) and records it; returns the saved row.
  ///
  /// The file is stored at `<ownerId>/<propertyId>/<timestamp>_<fileName>`.
  /// Throws [DocumentUploadFailure] when the upload fails and
  /// [PropertySaveFailure] when recording it fails (the file is removed).
  Future<PropertyDocument> uploadDocument({
    required String ownerId,
    required String propertyId,
    required DocumentKind kind,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? title,
    String? ownerRef,
  }) async {
    final path =
        '$ownerId/$propertyId/'
        '${_now().microsecondsSinceEpoch}_${_safeFileName(fileName)}';
    final bucket = _client.storage.from(documentsBucket);
    try {
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mimeType),
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(DocumentUploadFailure(error), stackTrace);
    }
    try {
      final row = await _client
          .from(_documents.name)
          .insert({
            'property_id': propertyId,
            'kind': kind.value,
            'storage_path': path,
            'file_name': fileName,
            'mime_type': mimeType,
            'size_bytes': bytes.length,
            'title': ?title,
            'owner_ref': ?ownerRef,
          })
          .select()
          .single();
      return PropertyDocument.fromJson(row);
    } on Object catch (error, stackTrace) {
      try {
        await bucket.remove([path]);
      } on Object {
        // Best effort: an orphan file only wastes storage.
      }
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Copies [document] (of another property of [ownerId]) into the
  /// property [toPropertyId]: the file is copied inside the bucket (no
  /// upload from the phone) to `<ownerId>/<toPropertyId>/…`, then recorded
  /// as a new document of the same kind; returns the saved row.
  ///
  /// The copy is independent of the original (deleting one keeps the
  /// other). Throws [DocumentUploadFailure] when the file cannot be copied
  /// (e.g. the destination is locked) and [PropertySaveFailure] when
  /// recording it fails (the copied file is removed).
  Future<PropertyDocument> copyDocument(
    PropertyDocument document, {
    required String ownerId,
    required String toPropertyId,
  }) async {
    final name = document.fileName ?? document.storagePath.split('/').last;
    final path =
        '$ownerId/$toPropertyId/'
        '${_now().microsecondsSinceEpoch}_${_safeFileName(name)}';
    final bucket = _client.storage.from(documentsBucket);
    try {
      await bucket.copy(document.storagePath, path);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(DocumentUploadFailure(error), stackTrace);
    }
    try {
      final row = await _client
          .from(_documents.name)
          .insert({
            'property_id': toPropertyId,
            'kind': document.kind.value,
            'storage_path': path,
            'file_name': document.fileName,
            'mime_type': document.mimeType,
            'size_bytes': document.sizeBytes,
          })
          .select()
          .single();
      return PropertyDocument.fromJson(row);
    } on Object catch (error, stackTrace) {
      try {
        await bucket.remove([path]);
      } on Object {
        // Best effort: an orphan file only wastes storage.
      }
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Changes the [kind] of the document [id]; returns the saved row.
  ///
  /// Throws [PropertySaveFailure] on error.
  Future<PropertyDocument> updateDocumentKind(
    String id,
    DocumentKind kind,
  ) async {
    try {
      final row = await _client
          .from(_documents.name)
          .update({'kind': kind.value})
          .eq('id', id)
          .select()
          .single();
      return PropertyDocument.fromJson(row);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Deletes [document]: its row, then its file — only when the row was
  /// actually deleted (row level security keeps the documents of a locked
  /// dossier, whose files must then stay too).
  ///
  /// Throws [PropertyDeleteFailure] on error.
  Future<void> deleteDocument(PropertyDocument document) async {
    try {
      final deleted = await _client
          .from(_documents.name)
          .delete()
          .eq('id', document.id)
          .select('id');
      if (deleted.isEmpty) return;
      await _client.storage.from(documentsBucket).remove([
        document.storagePath,
      ]);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyDeleteFailure(error), stackTrace);
    }
  }

  /// Renames the document [id] ([title] null: the label of its kind);
  /// returns the saved row.
  ///
  /// Throws [PropertySaveFailure] on error.
  Future<PropertyDocument> renameDocument(String id, String? title) async {
    final trimmed = title?.trim();
    try {
      final row = await _client
          .from(_documents.name)
          .update({
            'title': trimmed == null || trimmed.isEmpty ? null : trimmed,
          })
          .eq('id', id)
          .select()
          .single();
      return PropertyDocument.fromJson(row);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Saves who may see the document [id] once buyers and notaries use
  /// Realesty (an identity document stays private); returns the saved
  /// value.
  ///
  /// Throws [PropertySaveFailure] on error.
  Future<Set<DocumentVisibility>> setDocumentVisibility(
    String id,
    Set<DocumentVisibility> visibility,
  ) async {
    try {
      final saved = await _client.rpc<List<dynamic>>(
        'set_document_visibility',
        params: {
          'p_document_id': id,
          'p_visibility': [for (final value in visibility) value.value],
        },
      );
      return {
        for (final value in saved)
          ?parseDbEnum(DocumentVisibility.values, value),
      };
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Records that the document [newId] (already added) replaces [oldId] —
  /// a rejected document, or an addition the expert has not verified.
  ///
  /// Throws [PropertySaveFailure] on error.
  Future<void> replaceDocument({
    required String oldId,
    required String newId,
  }) async {
    try {
      await _client.rpc<void>(
        'replace_document',
        params: {'p_old_id': oldId, 'p_new_id': newId},
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// The content of the file at [storagePath] (to share it).
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<Uint8List> downloadDocument(String storagePath) async {
    try {
      return await _client.storage.from(documentsBucket).download(storagePath);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  /// A temporary URL to download the file at [storagePath].
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<String> getDocumentUrl(
    String storagePath, {
    Duration expiresIn = const Duration(minutes: 10),
  }) async {
    try {
      return await _client.storage
          .from(documentsBucket)
          .createSignedUrl(storagePath, expiresIn.inSeconds);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  // ---------------------------------------------------------------------
  // Room photos and vision AI (EPIC-15).
  // ---------------------------------------------------------------------

  static const _roomPhotos = 'room_photos';

  /// Name of the Edge Function analysing a room photo.
  static const visionRoomFunction = 'vision-room';

  /// Name of the Edge Function reading a floor plan.
  static const planReaderFunction = 'plan-reader';

  /// Version of the consent to the vision AI the seller accepted in the
  /// app; the vision functions refuse a request without it.
  static const visionConsent = 'photo_analysis_v1';

  /// Where the photo [photoId] of the room [roomId] is stored.
  static String roomPhotoPath({
    required String ownerId,
    required String propertyId,
    required String roomId,
    required String photoId,
  }) => '$ownerId/$propertyId/photos/$roomId/$photoId.jpg';

  /// The photos of [propertyId] (only those of [roomId] when given), in
  /// their order.
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<List<RoomPhoto>> getRoomPhotos(
    String propertyId, {
    String? roomId,
  }) async {
    try {
      var query = _client
          .from(_roomPhotos)
          .select()
          .eq('property_id', propertyId);
      if (roomId != null) query = query.eq('room_id', roomId);
      final rows = await query
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      return [for (final row in rows) RoomPhoto.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  /// Uploads the JPEG [bytes] as the photo [photo] (whose id the app
  /// chose, see [roomPhotoPath]) and records it; returns the saved row.
  ///
  /// Retry-safe: the file is overwritten and a row already recorded (an
  /// earlier answer was lost) is returned as is. Throws
  /// [DocumentUploadFailure] when the upload fails, [RoomPhotoLimitFailure]
  /// when the room or the property has too many photos and
  /// [PropertySaveFailure] when recording fails. The file is removed only
  /// when the database refused the row (an answer lost on the network may
  /// hide a row that was recorded: see [discardRoomPhoto]).
  Future<RoomPhoto> uploadRoomPhoto(
    RoomPhoto photo, {
    required Uint8List bytes,
  }) async {
    final bucket = _client.storage.from(documentsBucket);
    try {
      await bucket.uploadBinary(
        photo.storagePath,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(DocumentUploadFailure(error), stackTrace);
    }
    try {
      final row = await _client
          .from(_roomPhotos)
          .insert(photo.toInsertJson())
          .select()
          .single();
      return RoomPhoto.fromJson(row);
    } on Object catch (error, stackTrace) {
      if (error is PostgrestException && error.code == _uniqueViolation) {
        final stored = await getRoomPhotos(
          photo.propertyId,
          roomId: photo.roomId,
        ).then<List<RoomPhoto>?>((photos) => photos, onError: (_) => null);
        final same = stored?.where((p) => p.id == photo.id);
        if (same != null && same.isNotEmpty) return same.first;
      }
      if (error is PostgrestException) {
        try {
          await bucket.remove([photo.storagePath]);
        } on Object {
          // Best effort: an orphan file only wastes storage.
        }
      }
      Error.throwWithStackTrace(
        error is PostgrestException &&
                error.message == 'room_photo_limit_reached'
            ? RoomPhotoLimitFailure(error)
            : PropertySaveFailure(error),
        stackTrace,
      );
    }
  }

  /// Deletes [photo]: its row, then its file — only when the row was
  /// actually deleted (a locked dossier keeps its photos).
  ///
  /// Throws [RoomPhotoRequiredFailure] when [photo] is the last photo of a
  /// main room of a submitted dossier and [PropertyDeleteFailure] on any
  /// other error.
  Future<void> deleteRoomPhoto(RoomPhoto photo) async {
    try {
      final deleted = await _client
          .from(_roomPhotos)
          .delete()
          .eq('id', photo.id)
          .select('id');
      if (deleted.isEmpty) return;
      await _client.storage.from(documentsBucket).remove([photo.storagePath]);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        error is PostgrestException && error.message == 'room_photo_required'
            ? RoomPhotoRequiredFailure(error)
            : PropertyDeleteFailure(error),
        stackTrace,
      );
    }
  }

  /// Gives up [photo], whose upload failed or was not confirmed: its row if
  /// it was recorded anyway, and its file (best effort, never throws).
  Future<void> discardRoomPhoto(RoomPhoto photo) async {
    try {
      await _client.from(_roomPhotos).delete().eq('id', photo.id);
    } on Object {
      // Best effort: the row may not exist.
    }
    try {
      await _client.storage.from(documentsBucket).remove([photo.storagePath]);
    } on Object {
      // Best effort: an orphan file only wastes storage.
    }
  }

  /// Deletes every photo of the room [roomId] (before the room itself):
  /// their rows, then the files of the rows deleted.
  ///
  /// Throws [PropertyDeleteFailure] on error.
  Future<void> deleteRoomPhotos(String roomId) async {
    try {
      final deleted = await _client
          .from(_roomPhotos)
          .delete()
          .eq('room_id', roomId)
          .select('storage_path');
      if (deleted.isEmpty) return;
      await _client.storage.from(documentsBucket).remove([
        for (final row in deleted) row['storage_path']! as String,
      ]);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyDeleteFailure(error), stackTrace);
    }
  }

  /// Stores the order of [photos] (EVERY photo of one room, their position
  /// in the list; the server refuses a partial list) in one transaction
  /// (RPC `reorder_room_photos`: all or nothing); returns the photos of
  /// the room in their new order. Nothing is written when the order does
  /// not change.
  ///
  /// Throws [PropertySaveFailure] on error.
  Future<List<RoomPhoto>> reorderRoomPhotos(List<RoomPhoto> photos) async {
    if (photos.indexed.every((entry) => entry.$2.sortOrder == entry.$1)) {
      return photos;
    }
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'reorder_room_photos',
        params: {
          'p_room_id': photos.first.roomId,
          'p_photo_ids': [for (final photo in photos) photo.id],
        },
      );
      return [
        for (final row in rows) RoomPhoto.fromJson(row as Map<String, dynamic>),
      ];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  /// Temporary URLs of the files at [paths] (photos), by path; a file that
  /// cannot be signed is left out.
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<Map<String, String>> getPhotoUrls(
    List<String> paths, {
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    if (paths.isEmpty) return const {};
    try {
      final results = await _client.storage
          .from(documentsBucket)
          .createSignedUrlsResult(paths, expiresIn.inSeconds);
      return {
        for (final result in results)
          if (result case SignedUrlSuccess(:final path, :final signedUrl))
            path: signedUrl,
      };
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  /// Asks the vision AI to analyse the photo [photoId] (once: a stored
  /// analysis is returned as is) and returns its suggestions.
  ///
  /// Throws [VisionQuotaFailure] when the daily quota is used up,
  /// [VisionBusyFailure] when the photo is being analysed by another
  /// request and [VisionRequestFailure] on any other error.
  Future<RoomPhotoAnalysis> analyzeRoomPhoto(String photoId) async {
    final data = await _invokeVision(visionRoomFunction, {'photo_id': photoId});
    return RoomPhotoAnalysis.fromJson(
      data['analysis']! as Map<String, dynamic>,
    );
  }

  /// Asks the vision AI to read the floor plan [documentId] (a `plan`
  /// document, JPEG or PNG) and returns the rooms printed on it.
  ///
  /// Throws [VisionQuotaFailure] when the daily quota is used up,
  /// [VisionBusyFailure] when the plan is being read by another request
  /// and [VisionRequestFailure] on any other error.
  Future<PlanReading> readPlan(String documentId) async {
    final data = await _invokeVision(planReaderFunction, {
      'document_id': documentId,
    });
    return PlanReading.fromJson(data['reading']! as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _invokeVision(
    String function,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _client.functions.invoke(
        function,
        body: {...body, 'consent': visionConsent},
      );
      return response.data as Map<String, dynamic>;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(switch (error) {
        FunctionException(status: 429) => VisionQuotaFailure(error),
        FunctionException(status: 409, details: {'error': 'busy'}) =>
          VisionBusyFailure(error),
        _ => VisionRequestFailure(error),
      }, stackTrace);
    }
  }

  // ---------------------------------------------------------------------
  // Sale lots (EPIC-13).
  // ---------------------------------------------------------------------

  static const _lots = 'property_lots';

  /// Every sale lot of [ownerId], oldest first.
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<List<PropertyLot>> listLots(String ownerId) async {
    try {
      final rows = await _client
          .from(_lots)
          .select()
          .eq(PropertyLotColumns.ownerId, ownerId)
          .order(PropertyLotColumns.createdAt, ascending: true);
      return [for (final row in rows) PropertyLot.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  /// Creates the lot [id] (chosen by the app) with [propertyIds] as its
  /// properties, the first one as main property, and returns it: all or
  /// nothing, in one transaction (database function `create_property_lot`).
  /// Retry-safe: an existing lot [id] is reused.
  ///
  /// Throws [LotFrozenFailure] when a property is in a frozen lot and
  /// [PropertySaveFailure] on any other error.
  Future<PropertyLot> createLotWith({
    required String id,
    required List<String> propertyIds,
    LotSaleMode saleMode = LotSaleMode.together,
    String? name,
  }) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'create_property_lot',
        params: {
          'p_lot_id': id,
          'p_property_ids': propertyIds,
          'p_sale_mode': saleMode.value,
          'p_name': name,
        },
      );
      return PropertyLot.fromJson(row);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_saveFailure(error), stackTrace);
    }
  }

  /// Updates the columns of [patch] (`name`, `sale_mode`,
  /// `main_property_id`, keys from [PropertyLotColumns]) of the lot [id]
  /// and returns it.
  ///
  /// Throws [LotFrozenFailure] when nothing was updated (the lot is frozen,
  /// or gone) and [PropertySaveFailure] on error.
  Future<PropertyLot> updateLot(String id, Map<String, Object?> patch) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client
          .from(_lots)
          .update(encodeDbValue(patch)! as Map<String, Object?>)
          .eq(PropertyLotColumns.id, id)
          .select();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
    if (rows.isEmpty) throw LotFrozenFailure(id);
    return PropertyLot.fromJson(rows.single);
  }

  /// Deletes the lot [id]; its properties leave it.
  ///
  /// Throws [LotFrozenFailure] when it was not deleted (frozen) and
  /// [PropertyDeleteFailure] on error.
  Future<void> deleteLot(String id) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client
          .from(_lots)
          .delete()
          .eq(PropertyLotColumns.id, id)
          .select(PropertyLotColumns.id);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyDeleteFailure(error), stackTrace);
    }
    if (rows.isEmpty) throw LotFrozenFailure(id);
  }

  /// Puts the property [propertyId] in the lot [lotId] (null: out of its
  /// lot) and returns it.
  ///
  /// Throws [LotFrozenFailure] when the lot it joins or leaves is frozen,
  /// [PropertyNotFoundFailure] when the property cannot change (locked) and
  /// [PropertySaveFailure] on error.
  Future<Property> setPropertyLot(String propertyId, String? lotId) async {
    try {
      return await updateProperty(propertyId, {PropertyColumns.lotId: lotId});
    } on PropertySaveFailure catch (failure, stackTrace) {
      Error.throwWithStackTrace(_saveFailure(failure.error!), stackTrace);
    }
  }

  // ---------------------------------------------------------------------
  // Non-certified estimate (EPIC-05).
  // ---------------------------------------------------------------------

  static const _marketSnapshots = 'market_snapshots';

  /// Name of the Edge Function computing the estimate.
  static const estimateFunction = 'estimate-property';

  /// The estimate of property [propertyId]: its definitive result when
  /// there is one, else the latest attempt (running or failed), else null.
  ///
  /// Throws [PropertyLoadFailure] on error.
  Future<MarketSnapshot?> getMarketSnapshot(String propertyId) async {
    try {
      final rows = await _client
          .from(_marketSnapshots)
          .select()
          .eq('property_id', propertyId)
          .order('created_at', ascending: false)
          .limit(10);
      final snapshots = rows.map(MarketSnapshot.fromJson).toList();
      for (final snapshot in snapshots) {
        if (snapshot.isFinal) return snapshot;
      }
      return snapshots.firstOrNull;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertyLoadFailure(error), stackTrace);
    }
  }

  /// Asks the backend to compute the estimate of the sent dossier
  /// [propertyId]. Idempotent: an existing result is never recomputed, and
  /// the computation goes on in the background (read it with
  /// [getMarketSnapshot]).
  ///
  /// Throws [EstimateRateLimitFailure] when the user asked for too many
  /// estimates, [EstimateRequestFailure] on any other error.
  Future<void> requestEstimate(String propertyId) async {
    try {
      await _client.functions.invoke(
        estimateFunction,
        body: {'property_id': propertyId},
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        error is FunctionException && error.status == 429
            ? EstimateRateLimitFailure(error)
            : EstimateRequestFailure(error),
        stackTrace,
      );
    }
  }

  static String _safeFileName(String fileName) =>
      fileName.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
}

/// A child table: its name, default order and row parser.
class _Table<T> {
  const new(this.name, this.orderBy, this.fromJson);

  final String name;
  final String orderBy;
  final T Function(Map<String, dynamic> json) fromJson;
}
