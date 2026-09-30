import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:profile_repository/profile_repository.dart';

part 'profile_state.dart';

/// Profile of the signed-in user: loaded whenever the user changes, and
/// updated when a role is chosen.
class ProfileCubit extends Cubit<ProfileState> {
  new({
    required AuthRepository authRepository,
    required this._profileRepository,
  }) : super(const ProfileState()) {
    _userSubscription = authRepository.user.listen(_onUserChanged);
  }

  final ProfileRepository _profileRepository;
  late final StreamSubscription<AuthUser?> _userSubscription;

  String? _userId;

  void _onUserChanged(AuthUser? user) {
    if (user?.id == _userId) return;
    _userId = user?.id;
    if (user == null) {
      emit(const ProfileState());
    } else {
      unawaited(_load(user.id));
    }
  }

  /// Loads the profile again, after a failure.
  void retry() {
    final userId = _userId;
    if (userId == null) return;
    unawaited(_load(userId));
  }

  Future<void> _load(String userId) async {
    emit(const ProfileState(status: ProfileStatus.loading));
    try {
      final profile = await _profileRepository.getProfile(userId);
      if (isClosed || userId != _userId) return;
      emit(ProfileState(status: ProfileStatus.success, profile: profile));
    } on Object catch (error, stackTrace) {
      if (isClosed || userId != _userId) return;
      addError(error, stackTrace);
      emit(const ProfileState(status: ProfileStatus.failure));
    }
  }

  /// Saves the [role] chosen by the user.
  Future<void> selectRole(UserRole role) async {
    final profile = state.profile;
    if (profile == null ||
        state.roleUpdateStatus == RoleUpdateStatus.inProgress) {
      return;
    }
    emit(state.copyWith(roleUpdateStatus: RoleUpdateStatus.inProgress));
    try {
      await _profileRepository.updateRole(profile.id, role);
    } on Object catch (error, stackTrace) {
      if (isClosed || profile.id != _userId) return;
      addError(error, stackTrace);
      emit(state.copyWith(roleUpdateStatus: RoleUpdateStatus.failure));
      return;
    }
    if (isClosed || profile.id != _userId) return;
    emit(
      ProfileState(
        status: ProfileStatus.success,
        profile: Profile(
          id: profile.id,
          firstName: profile.firstName,
          role: role,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await super.close();
  }
}
