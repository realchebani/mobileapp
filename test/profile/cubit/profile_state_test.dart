import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:profile_repository/profile_repository.dart';

void main() {
  group(ProfileState, () {
    const state = ProfileState(
      status: ProfileStatus.success,
      profile: Profile(id: 'id'),
      roleUpdateStatus: RoleUpdateStatus.inProgress,
    );

    test('copyWith keeps the values not given', () {
      expect(state.copyWith(), state);
    });

    test('copyWith updates the role update status', () {
      expect(
        state.copyWith(roleUpdateStatus: RoleUpdateStatus.failure),
        const ProfileState(
          status: ProfileStatus.success,
          profile: Profile(id: 'id'),
          roleUpdateStatus: RoleUpdateStatus.failure,
        ),
      );
    });
  });
}
