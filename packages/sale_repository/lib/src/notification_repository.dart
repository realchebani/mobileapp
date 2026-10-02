import 'package:sale_repository/sale_repository.dart';
import 'package:supabase/supabase.dart';

/// {@template notification_failure}
/// Thrown when reading or updating notifications fails.
/// {@endtemplate}
class NotificationFailure implements Exception {
  /// {@macro notification_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'NotificationFailure($error)';
}

/// {@template notification_repository}
/// In-app notifications of the signed-in user (`notifications` table, filled
/// by staff functions; the app only marks them read).
/// {@endtemplate}
class NotificationRepository {
  /// {@macro notification_repository}
  new({required this._client, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SupabaseClient _client;
  final DateTime Function() _now;

  static const _table = 'notifications';

  /// The [limit] latest notifications of [userId], newest first.
  ///
  /// Throws [NotificationFailure] on error.
  Future<List<AppNotification>> getNotifications(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .from(_table)
          .select(
            'id, kind, title, body, property_id, route, read_at, created_at',
          )
          .eq('user_id', userId)
          .order('created_at')
          .limit(limit);
      return [for (final row in rows) AppNotification.fromJson(row)];
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(NotificationFailure(error), stackTrace);
    }
  }

  /// Marks the notifications [ids] read (now) and returns that time.
  ///
  /// Throws [NotificationFailure] on error.
  Future<DateTime> markRead(List<String> ids) async {
    final now = _now();
    if (ids.isEmpty) return now;
    try {
      await _client
          .from(_table)
          .update({'read_at': now.toUtc().toIso8601String()})
          .inFilter('id', ids)
          .isFilter('read_at', null);
      return now;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(NotificationFailure(error), stackTrace);
    }
  }
}
