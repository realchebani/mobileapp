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

  /// Deletes the draft [property]: its document files first (the storage
  /// rules need the property to still exist), then the property, whose
  /// child rows go with it.
  ///
  /// Throws [PropertyDeleteFailure] when the property is not a draft or on
  /// error.
  Future<void> deleteProperty(Property property) async {
    if (property.status != PropertyStatus.draft) {
      throw PropertyDeleteFailure('${property.id} is not a draft');
    }
    try {
      final folder = '${property.ownerId}/${property.id}';
      final bucket = _client.storage.from(documentsBucket);
      final files = await bucket.list(path: folder);
      if (files.isNotEmpty) {
        await bucket.remove([for (final file in files) '$folder/${file.name}']);
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

  /// Documents of [propertyId], oldest first.
  Future<List<PropertyDocument>> getDocuments(String propertyId) =>
      _list(_documents, propertyId);

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

  /// Creates the lot [id] of [ownerId] (id chosen by the app, retry-safe:
  /// an existing lot [id] is returned as is) and returns it.
  ///
  /// Throws [PropertySaveFailure] on error.
  Future<PropertyLot> createLot({
    required String id,
    required String ownerId,
    String? name,
    LotSaleMode saleMode = LotSaleMode.together,
  }) async {
    try {
      final row = await _client
          .from(_lots)
          .insert({
            PropertyLotColumns.id: id,
            PropertyLotColumns.ownerId: ownerId,
            PropertyLotColumns.name: ?name,
            PropertyLotColumns.saleMode: saleMode.value,
          })
          .select()
          .single();
      return PropertyLot.fromJson(row);
    } on PostgrestException catch (error, stackTrace) {
      if (error.code == _uniqueViolation) {
        final existing = await _maybeLot(id);
        if (existing != null) return existing;
      }
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PropertySaveFailure(error), stackTrace);
    }
  }

  Future<PropertyLot?> _maybeLot(String id) async {
    try {
      final row = await _client
          .from(_lots)
          .select()
          .eq(PropertyLotColumns.id, id)
          .maybeSingle();
      return row == null ? null : PropertyLot.fromJson(row);
    } on Object {
      return null;
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
