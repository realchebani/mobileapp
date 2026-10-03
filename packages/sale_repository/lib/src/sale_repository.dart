import 'dart:typed_data';

import 'package:sale_repository/sale_repository.dart';
import 'package:supabase/supabase.dart';

/// Why a sale action was refused (the code raised by the SQL functions of
/// `*_mise_en_vente.sql`), or [unknown] for any other error.
enum SaleFailureReason {
  propertyNotCertified('property_not_certified'),
  mainPropertyNotCertified('main_property_not_certified'),
  lotSoldTogether('lot_sold_together'),
  lotOnSale('lot_on_sale'),
  memberOnSale('member_on_sale'),
  mandateAlreadySigned('mandate_already_signed'),
  termsNotAccepted('terms_not_accepted'),
  signatureMissing('signature_missing'),
  identityDocumentMissing('identity_document_missing'),
  identityNotVerified('identity_not_verified'),
  priceOutOfBounds('price_out_of_bounds'),
  missingPrice('missing_price'),
  mandateMinimumPeriod('mandate_minimum_period'),
  premiumOnly('premium_only'),
  slotInPast('slot_in_past'),
  requestAlreadyOpen('request_already_open'),
  publishIncomplete('publish_incomplete'),
  mandateNotSigned('mandate_not_signed'),
  photoLimitReached('listing_photo_limit_reached'),
  saleNotFound('sale_not_found'),
  unknown('');

  new(this.code);

  /// Message of the database exception.
  final String code;

  static SaleFailureReason of(Object? error) {
    if (error is! PostgrestException) return unknown;
    for (final reason in values) {
      if (reason != unknown && error.message.contains(reason.code)) {
        return reason;
      }
    }
    return unknown;
  }
}

/// What a listing lacks to be published
/// ([SaleFailureReason.publishIncomplete]).
enum PublishMissing {
  price('missing_price'),
  title('missing_title'),
  description('missing_description'),
  photos('missing_photos');

  new(this.code);

  final String code;
}

/// {@template sale_failure}
/// Thrown when a sale action fails.
/// {@endtemplate}
class SaleFailure implements Exception {
  /// {@macro sale_failure}
  const new(this.reason, {this.missing = const [], this.details, this.error});

  /// A failure built from a database / network [error].
  factory from(Object error) {
    final reason = SaleFailureReason.of(error);
    final details = error is PostgrestException ? '${error.details}' : '';
    return SaleFailure(
      reason,
      missing: [
        for (final item in PublishMissing.values)
          if (details.contains(item.code)) item,
      ],
      details: details.isEmpty || details == 'null' ? null : details,
      error: error,
    );
  }

  /// Detail of the database error (bounds of a price, end of a period).
  final String? details;

  /// The first day the mandate can be ended
  /// ([SaleFailureReason.mandateMinimumPeriod]).
  DateTime? get endableFrom => DateTime.tryParse(details ?? '');

  /// The allowed bounds of the price ([SaleFailureReason.priceOutOfBounds]).
  (int, int)? get priceBounds {
    final parts = (details ?? '').split(',');
    if (parts.length != 2) return null;
    final low = int.tryParse(parts.first);
    final high = int.tryParse(parts.last);
    return low == null || high == null ? null : (low, high);
  }

  final SaleFailureReason reason;

  /// What is missing to publish ([SaleFailureReason.publishIncomplete]).
  final List<PublishMissing> missing;

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'SaleFailure($reason, $missing, $details, $error)';
}

/// {@template sale_repository}
/// The sales of the signed-in seller (EPIC-08): formula, TEST mandate,
/// service requests, listing and its photos. State changes go through the
/// SQL functions (RPC); files live in the private buckets
/// `mandate-signatures`, `sale-documents` and `listing-media`.
/// {@endtemplate}
class SaleRepository {
  /// {@macro sale_repository}
  const new({required this._client});

  final SupabaseClient _client;

  static const _sales = 'sales';
  static const _mandates = 'mandates';
  static const _requests = 'sale_requests';
  static const _photos = 'listing_photos';

  /// Bucket of the drawn signatures.
  static const signaturesBucket = 'mandate-signatures';

  /// Bucket of the generated mandates (PDF).
  static const documentsBucket = 'sale-documents';

  /// Bucket of the listing photos.
  static const mediaBucket = 'listing-media';

  /// Bucket of the dossier photos (`property_repository`).
  static const dossierBucket = 'property-documents';

  /// Edge Function rendering the mandate PDF.
  static const renderMandateFunction = 'render-mandate';

  /// Version of the test mandate terms (same as the SQL
  /// `sale_terms_version()` and the Edge Function template).
  static const termsVersion = 'test-2026-10-b';

  /// Columns of `sale_requests` the app can read.
  static const _requestColumns =
      'id, sale_id, kind, diagnostics, preferred_slots, status, '
      'scheduled_at, price_eur_ttc, created_at';

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(SaleFailure.from(error), stackTrace);
    }
  }

  /// The active sales (not withdrawn) of [ownerId], oldest first.
  Future<List<Sale>> listSales(String ownerId) => _run(() async {
    final rows = await _client
        .from(_sales)
        .select()
        .eq(SaleColumns.ownerId, ownerId)
        .neq(SaleColumns.stage, SaleStage.withdrawn.value)
        .order(SaleColumns.createdAt, ascending: true);
    return [for (final row in rows) Sale.fromJson(row)];
  });

  /// The sale [id], or null when the user cannot see it.
  Future<Sale?> getSale(String id) => _run(() async {
    final row = await _client
        .from(_sales)
        .select()
        .eq(SaleColumns.id, id)
        .maybeSingle();
    return row == null ? null : Sale.fromJson(row);
  });

  /// Creates the sale [saleId] of a property or a lot with [formula], or
  /// changes the formula of its active sale (mandate not signed); returns
  /// the id of the sale (the existing one when the target already had one).
  Future<String> chooseFormula({
    required String saleId,
    required SaleFormula formula,
    String? propertyId,
    String? lotId,
  }) => _run(() async {
    final id = await _client.rpc<String>(
      'choose_formula',
      params: {
        'p_sale_id': saleId,
        'p_property_id': propertyId,
        'p_lot_id': lotId,
        'p_formula': formula.value,
      },
    );
    return id;
  });

  /// Changes listing columns of the sale [id] (price, title, description,
  /// preferences) and returns it.
  Future<Sale> updateSale(String id, Map<String, Object?> patch) =>
      _run(() async {
        final row = await _client
            .from(_sales)
            .update(patch)
            .eq(SaleColumns.id, id)
            .select()
            .single();
        return Sale.fromJson(row);
      });

  /// The latest mandate of the sale [saleId], if any.
  Future<Mandate?> getMandate(String saleId) => _run(() async {
    final row = await _client
        .from(_mandates)
        .select()
        .eq('sale_id', saleId)
        .order('signed_at')
        .limit(1)
        .maybeSingle();
    return row == null ? null : Mandate.fromJson(row);
  });

  /// Path of a drawn signature in [signaturesBucket].
  static String signaturePath({
    required String ownerId,
    required String saleId,
    required String mandateId,
  }) => '$ownerId/$saleId/$mandateId.png';

  /// Signs the TEST mandate [mandateId] (id chosen by the app, retry-safe)
  /// of the sale [saleId] with the drawn [signaturePng], or the name the
  /// seller typed ([typedName], accessibility); returns the mandate id.
  Future<String> signTestMandate({
    required String ownerId,
    required String saleId,
    required String mandateId,
    required bool accepted,
    Uint8List? signaturePng,
    String? typedName,
    String? userAgent,
    String? appVersion,
  }) => _run(() async {
    final path = signaturePng == null
        ? null
        : signaturePath(ownerId: ownerId, saleId: saleId, mandateId: mandateId);
    if (signaturePng != null) {
      try {
        await _client.storage
            .from(signaturesBucket)
            .uploadBinary(
              path!,
              signaturePng,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );
      } on StorageException catch (error) {
        // Sent by an earlier attempt whose answer was lost.
        if (!_alreadyExists(error)) rethrow;
      }
    }
    return await _client.rpc<String>(
      'sign_test_mandate',
      params: {
        'p_sale_id': saleId,
        'p_mandate_id': mandateId,
        'p_terms_version': termsVersion,
        'p_signature_path': path,
        'p_accepted': accepted,
        'p_user_agent': userAgent,
        'p_app_version': appVersion,
        'p_typed_name': typedName,
      },
    );
  });

  static bool _alreadyExists(StorageException error) =>
      error.statusCode == '409' ||
      error.message.toLowerCase().contains('already exists') ||
      error.message.toLowerCase().contains('duplicate');

  /// Asks the server to render the PDF of [mandateId] (idempotent);
  /// returns its path in [documentsBucket].
  Future<String> renderMandate(String mandateId) => _run(() async {
    final response = await _client.functions.invoke(
      renderMandateFunction,
      body: {'mandate_id': mandateId},
    );
    return (response.data as Map<String, dynamic>)['path'] as String;
  });

  /// A temporary URL of the mandate PDF at [path].
  Future<String> mandateUrl(String path) => _run(
    () => _client.storage.from(documentsBucket).createSignedUrl(path, 600),
  );

  /// The service requests of the sale [saleId], oldest first.
  Future<List<SaleRequest>> getRequests(String saleId) => _run(() async {
    final rows = await _client
        .from(_requests)
        .select(_requestColumns)
        .eq('sale_id', saleId)
        .order('created_at', ascending: true);
    return [for (final row in rows) SaleRequest.fromJson(row)];
  });

  /// Asks a service (id chosen by the app, retry-safe) and returns it.
  Future<SaleRequest> requestService({
    required String requestId,
    required String saleId,
    required SaleRequestKind kind,
    List<Diagnostic> diagnostics = const [],
    List<DateTime> preferredSlots = const [],
  }) => _run(() async {
    await _client.rpc<Object?>(
      'request_sale_service',
      params: {
        'p_request_id': requestId,
        'p_sale_id': saleId,
        'p_kind': kind.value,
        'p_diagnostics': [for (final d in diagnostics) d.value],
        'p_preferred_slots': [
          for (final slot in preferredSlots) slot.toUtc().toIso8601String(),
        ],
      },
    );
    final row = await _client
        .from(_requests)
        .select(_requestColumns)
        .eq('id', requestId)
        .single();
    return SaleRequest.fromJson(row);
  });

  /// Cancels the open request [requestId].
  Future<void> cancelRequest(String requestId) => _run(
    () => _client.rpc<Object?>(
      'cancel_sale_request',
      params: {'p_request_id': requestId},
    ),
  );

  /// Publishes the listing of [saleId]; throws a [SaleFailure] with
  /// [SaleFailure.missing] when something is missing.
  Future<void> publish(String saleId) => _run(
    () =>
        _client.rpc<Object?>('publish_listing', params: {'p_sale_id': saleId}),
  );

  /// Takes the listing of [saleId] offline.
  Future<void> unpublish(String saleId) => _run(
    () => _client.rpc<Object?>(
      'unpublish_listing',
      params: {'p_sale_id': saleId},
    ),
  );

  /// Withdraws the sale [saleId] (listing removed, test mandate ended).
  Future<void> withdraw(String saleId, {String? reason}) => _run(
    () => _client.rpc<Object?>(
      'withdraw_sale',
      params: {'p_sale_id': saleId, 'p_reason': reason},
    ),
  );

  /// The identity verification of the owners of [propertyId], by owner id.
  Future<Map<String, DateTime?>> getIdentityVerifications(String propertyId) =>
      _run(() async {
        final rows = await _client
            .from('property_owners')
            .select('id, identity_verified_at')
            .eq('property_id', propertyId);
        return {
          for (final row in rows)
            row['id'] as String: row['identity_verified_at'] == null
                ? null
                : DateTime.parse(row['identity_verified_at'] as String),
        };
      });

  // Listing photos -----------------------------------------------------------

  /// Path of a listing photo in [mediaBucket].
  static String listingPhotoPath({
    required String ownerId,
    required String saleId,
    required String photoId,
  }) => '$ownerId/$saleId/$photoId.jpg';

  /// The photos of the listing of [saleId], cover first.
  Future<List<ListingPhoto>> getListingPhotos(String saleId) => _run(() async {
    final rows = await _client
        .from(_photos)
        .select()
        .eq('sale_id', saleId)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    return [for (final row in rows) ListingPhoto.fromJson(row)];
  });

  /// Temporary URLs of the listing photos at [paths] (a file that cannot
  /// be signed is left out).
  Future<Map<String, String>> listingPhotoUrls(List<String> paths) =>
      _run(() async {
        if (paths.isEmpty) return const {};
        final results = await _client.storage
            .from(mediaBucket)
            .createSignedUrlsResult(paths, 3600);
        return {
          for (final result in results)
            if (result case SignedUrlSuccess(:final path, :final signedUrl))
              path: signedUrl,
        };
      });

  /// Adds [photo] to its listing, copying the dossier file at [sourcePath]
  /// (bucket [dossierBucket]) into [mediaBucket] (or downloading and
  /// sending it again when the copy is refused); retry-safe (a row already
  /// recorded is returned as is).
  Future<ListingPhoto> copyRoomPhoto(
    ListingPhoto photo, {
    required String sourcePath,
  }) => _run(() async {
    final existing = await _existing(photo.id) ?? await _copyOf(photo);
    if (existing != null) return existing;
    try {
      await _client.storage
          .from(dossierBucket)
          .copy(sourcePath, photo.storagePath, destinationBucket: mediaBucket);
    } on StorageException catch (error) {
      if (!_alreadyExists(error)) {
        // Copy across buckets refused: download and send it again.
        final bytes = await _client.storage
            .from(dossierBucket)
            .download(sourcePath);
        await _client.storage
            .from(mediaBucket)
            .uploadBinary(
              photo.storagePath,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
      }
    }
    try {
      return await _insert(photo);
    } on Object {
      // Recorded meanwhile by another attempt (one copy per source photo):
      // that row wins and this file is removed.
      await _removeQuietly(photo.storagePath);
      final other = await _copyOf(photo);
      if (other != null) return other;
      rethrow;
    }
  });

  /// The listing row already copied from the source of [photo], if any.
  Future<ListingPhoto?> _copyOf(ListingPhoto photo) async {
    final source = photo.sourceRoomPhotoId;
    if (source == null) return null;
    final row = await _client
        .from(_photos)
        .select()
        .eq('sale_id', photo.saleId)
        .eq('source_room_photo_id', source)
        .maybeSingle();
    return row == null ? null : ListingPhoto.fromJson(row);
  }

  Future<void> _removeQuietly(String path) async {
    try {
      await _client.storage.from(mediaBucket).remove([path]);
    } on Object {
      // Orphan file: listed by the team (runbook).
    }
  }

  /// Adds [photo] to its listing with the JPEG [bytes] (a new photo);
  /// retry-safe.
  Future<ListingPhoto> uploadListingPhoto(
    ListingPhoto photo, {
    required Uint8List bytes,
  }) => _run(() async {
    final existing = await _existing(photo.id);
    if (existing != null) return existing;
    await _client.storage
        .from(mediaBucket)
        .uploadBinary(
          photo.storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return await _insert(photo);
  });

  Future<ListingPhoto?> _existing(String id) async {
    final row = await _client.from(_photos).select().eq('id', id).maybeSingle();
    return row == null ? null : ListingPhoto.fromJson(row);
  }

  Future<ListingPhoto> _insert(ListingPhoto photo) async {
    final row = await _client
        .from(_photos)
        .insert(photo.toJson())
        .select()
        .single();
    return ListingPhoto.fromJson(row);
  }

  /// Removes [photo] from its listing (row, then file).
  Future<void> deleteListingPhoto(ListingPhoto photo) => _run(() async {
    await _client.from(_photos).delete().eq('id', photo.id);
    await _client.storage.from(mediaBucket).remove([photo.storagePath]);
  });

  /// Puts the photos of the listing of [saleId] in the order [photoIds]
  /// (all of them; the first one is the cover) and returns them.
  Future<List<ListingPhoto>> reorderListingPhotos(
    String saleId,
    List<String> photoIds,
  ) => _run(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'reorder_listing_photos',
      params: {'p_sale_id': saleId, 'p_photo_ids': photoIds},
    );
    return [
      for (final row in rows)
        ListingPhoto.fromJson(row as Map<String, dynamic>),
    ];
  });
}
