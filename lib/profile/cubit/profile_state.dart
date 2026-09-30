part of 'profile_cubit.dart';

enum ProfileStatus {
  /// No signed-in user.
  initial,

  /// The profile of the signed-in user is being loaded.
  loading,

  /// The profile is loaded, see [ProfileState.profile].
  success,

  /// The profile could not be loaded.
  failure,
}

/// Progress of [ProfileCubit.selectRole].
enum RoleUpdateStatus { idle, inProgress, failure }

final class ProfileState extends Equatable {
  const new({
    this.status = ProfileStatus.initial,
    this.profile,
    this.roleUpdateStatus = RoleUpdateStatus.idle,
  });

  final ProfileStatus status;

  /// The profile of the signed-in user, once loaded.
  final Profile? profile;

  final RoleUpdateStatus roleUpdateStatus;

  ProfileState copyWith({RoleUpdateStatus? roleUpdateStatus}) {
    return ProfileState(
      status: status,
      profile: profile,
      roleUpdateStatus: roleUpdateStatus ?? this.roleUpdateStatus,
    );
  }

  @override
  List<Object?> get props => [status, profile, roleUpdateStatus];
}
