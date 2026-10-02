import 'package:sale_repository/sale_repository.dart';
import 'package:supabase/supabase.dart';

/// {@template valuation_failure}
/// Thrown when reading a valuation or its PDF URL fails.
/// {@endtemplate}
class ValuationLoadFailure implements Exception {
  /// {@macro valuation_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'ValuationLoadFailure($error)';
}

/// {@template valuation_repository}
/// Reads the certified valuations of the user's properties (`valuations`
/// table, read-only for the app) and their PDF reports (private bucket
/// `valuation-reports`).
/// {@endtemplate}
class ValuationRepository {
  /// {@macro valuation_repository}
  const new({required this._client});

  final SupabaseClient _client;

  static const _table = 'valuations';

  /// Storage bucket of the PDF reports.
  static const reportsBucket = 'valuation-reports';

  /// The latest valuation of [propertyId], or null when there is none.
  ///
  /// Throws [ValuationLoadFailure] on error.
  Future<Valuation?> getLatestValuation(String propertyId) async {
    try {
      final row = await _client
          .from(_table)
          .select()
          .eq(ValuationColumns.propertyId, propertyId)
          .order(ValuationColumns.certifiedAt)
          .limit(1)
          .maybeSingle();
      return row == null ? null : Valuation.fromJson(row);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(ValuationLoadFailure(error), stackTrace);
    }
  }

  /// A temporary URL to download the PDF at [storagePath].
  ///
  /// Throws [ValuationLoadFailure] on error.
  Future<String> getReportUrl(
    String storagePath, {
    Duration expiresIn = const Duration(minutes: 10),
  }) async {
    try {
      return await _client.storage
          .from(reportsBucket)
          .createSignedUrl(storagePath, expiresIn.inSeconds);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(ValuationLoadFailure(error), stackTrace);
    }
  }
}
