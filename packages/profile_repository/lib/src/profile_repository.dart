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
  static const _columns = 'id, first_name, role';

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
}
