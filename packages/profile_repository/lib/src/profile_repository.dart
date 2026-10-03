import 'package:profile_repository/profile_repository.dart';
import 'package:supabase/supabase.dart';

/// {@template profile_not_found_failure}
/// Thrown when the requested profile does not exist or is not visible
/// to the current user.
/// {@endtemplate}
class ProfileNotFoundFailure implements Exception {
  /// {@macro profile_not_found_failure}
  const new(this.userId);

  /// Identifier of the missing profile.
  final String userId;

  @override
  String toString() => 'ProfileNotFoundFailure($userId)';
}

/// {@template get_profile_failure}
/// Thrown when [ProfileRepository.getProfile] fails.
/// {@endtemplate}
class GetProfileFailure implements Exception {
  /// {@macro get_profile_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'GetProfileFailure($error)';
}

/// {@template update_role_failure}
/// Thrown when [ProfileRepository.updateRole] fails.
/// {@endtemplate}
class UpdateRoleFailure implements Exception {
  /// {@macro update_role_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'UpdateRoleFailure($error)';
}

/// {@template update_profile_failure}
/// Thrown when [ProfileRepository.updateDetails] or
/// [ProfileRepository.updateLocale] fails.
/// {@endtemplate}
class UpdateProfileFailure implements Exception {
  /// {@macro update_profile_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'UpdateProfileFailure($error)';
}

/// What prevents a user from deleting their account.
enum AccountDeletionBlocker {
  /// A property is on sale (mandate signed or listing published, EPIC-08).
  activeSale('active_sale'),

  /// The user is a member of the Realesty team (EPIC-12).
  staffAccount('staff_account');

  new(this.value);

  /// Code returned by the database.
  final String value;

  /// The blocker of [code], or null for an unknown one.
  static AccountDeletionBlocker? tryParse(Object? code) {
    for (final blocker in values) {
      if (blocker.value == code) return blocker;
    }
    return null;
  }
}

/// {@template account_deletion_failure}
/// Thrown when the account cannot be deactivated or reactivated, or its
/// blockers cannot be read.
/// {@endtemplate}
class AccountDeletionFailure implements Exception {
  /// {@macro account_deletion_failure}
  const new({this.blocker, this.error});

  /// Builds the failure matching an error of the database.
  factory fromError(Object error) => AccountDeletionFailure(
    blocker: error is PostgrestException
        ? AccountDeletionBlocker.tryParse(error.message)
        : null,
    error: error,
  );

  /// Why the deletion was refused, when it was (else a technical error).
  final AccountDeletionBlocker? blocker;

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'AccountDeletionFailure($blocker, $error)';
}

/// {@template profile_repository}
/// Reads and writes user profiles in the Supabase `profiles` table.
///
/// Row level security only lets a signed-in user access their own row.
/// {@endtemplate}
class ProfileRepository {
  /// {@macro profile_repository}
  const new({required this._client});

  final SupabaseClient _client;

  static const _table = 'profiles';
  static const _columns =
      'id, first_name, role, last_name, phone, postal_address, locale, '
      'deactivated_at, deletion_due_at';

  /// Returns the profile of [userId].
  ///
  /// Throws [ProfileNotFoundFailure] when there is no such profile and
  /// [GetProfileFailure] on any other error.
  Future<Profile> getProfile(String userId) async {
    final Map<String, dynamic>? row;
    try {
      row = await _client
          .from(_table)
          .select(_columns)
          .eq('id', userId)
          .maybeSingle();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(GetProfileFailure(error), stackTrace);
    }
    if (row == null) throw ProfileNotFoundFailure(userId);
    return Profile.fromJson(row);
  }

  /// Sets the role of [userId].
  ///
  /// Throws [ProfileNotFoundFailure] when no profile was updated and
  /// [UpdateRoleFailure] on any other error.
  Future<void> updateRole(String userId, UserRole role) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client
          .from(_table)
          .update({'role': role.name})
          .eq('id', userId)
          .select('id');
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(UpdateRoleFailure(error), stackTrace);
    }
    if (rows.isEmpty) throw ProfileNotFoundFailure(userId);
  }

  /// Saves the personal information of [userId] (V19); returns the profile.
  ///
  /// Throws [ProfileNotFoundFailure] when no profile was updated and
  /// [UpdateProfileFailure] on any other error.
  Future<Profile> updateDetails(String userId, ProfileDetails details) =>
      _update(userId, details.toJson());

  /// Saves the language chosen in the app ([locale] null = the device's).
  ///
  /// Throws [ProfileNotFoundFailure] when no profile was updated and
  /// [UpdateProfileFailure] on any other error.
  Future<Profile> updateLocale(String userId, String? locale) =>
      _update(userId, {'locale': locale});

  Future<Profile> _update(String userId, Map<String, Object?> patch) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client
          .from(_table)
          .update(patch)
          .eq('id', userId)
          .select(_columns);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(UpdateProfileFailure(error), stackTrace);
    }
    if (rows.isEmpty) throw ProfileNotFoundFailure(userId);
    return Profile.fromJson(rows.single);
  }

  /// What prevents the signed-in user from deleting their account (empty
  /// when nothing does).
  ///
  /// Throws [AccountDeletionFailure] on error.
  Future<Set<AccountDeletionBlocker>> getDeletionBlockers() async {
    try {
      final codes = await _client.rpc<List<dynamic>>(
        'account_deletion_blockers',
      );
      return {for (final code in codes) ?AccountDeletionBlocker.tryParse(code)};
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AccountDeletionFailure.fromError(error),
        stackTrace,
      );
    }
  }

  /// Deactivates the account of the signed-in user at once; it is deleted
  /// for good on the returned date unless reactivated before. Idempotent.
  ///
  /// Throws [AccountDeletionFailure] (with its [AccountDeletionBlocker]
  /// when refused).
  Future<DateTime> deactivateAccount() async {
    try {
      final due = await _client.rpc<String>('deactivate_account');
      return DateTime.parse(due);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AccountDeletionFailure.fromError(error),
        stackTrace,
      );
    }
  }

  /// Cancels the deletion of the signed-in user's account.
  ///
  /// Throws [AccountDeletionFailure] on error.
  Future<void> reactivateAccount() async {
    try {
      await _client.rpc<void>('reactivate_account');
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AccountDeletionFailure.fromError(error),
        stackTrace,
      );
    }
  }
}
