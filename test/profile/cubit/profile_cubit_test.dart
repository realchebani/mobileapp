import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  const user = AuthUser(id: 'user-id', email: 'jane@example.com');
  const otherUser = AuthUser(id: 'other-id');
  const profile = Profile(id: 'user-id', firstName: 'Jane');

  late AuthRepository authRepository;
  late ProfileRepository profileRepository;
  late StreamController<AuthUser?> userController;

  setUpAll(() => registerFallbackValue(UserRole.seller));

  setUp(() {
    authRepository = MockAuthRepository();
    profileRepository = MockProfileRepository();
    userController = StreamController<AuthUser?>();
    when(() => authRepository.user).thenAnswer((_) => userController.stream);
    when(() => profileRepository.getProfile(any()))
        .thenAnswer((_) async => profile);
    when(() => profileRepository.updateRole(any(), any()))
        .thenAnswer((_) async {});
  });

  ProfileCubit buildCubit() => ProfileCubit(
    authRepository: authRepository,
    profileRepository: profileRepository,
  );

  const loadedState = ProfileState(
    status: ProfileStatus.success,
    profile: profile,
  );

  group(ProfileCubit, () {
    test('initial state is initial', () {
      expect(buildCubit().state, const ProfileState());
    });

    blocTest<ProfileCubit, ProfileState>(
      'loads the profile when a user signs in',
      build: buildCubit,
      act: (_) => userController.add(user),
      expect: () => const [
        ProfileState(status: ProfileStatus.loading),
        loadedState,
      ],
      verify: (_) => verify(() => profileRepository.getProfile('user-id')),
    );

    blocTest<ProfileCubit, ProfileState>(
      'ignores a repeated user and resets on sign out',
      build: buildCubit,
      act: (_) async {
        userController.add(user);
        await Future<void>.delayed(Duration.zero);
        userController
          ..add(user)
          ..add(null)
          ..add(null);
      },
      expect: () => const [
        ProfileState(status: ProfileStatus.loading),
        loadedState,
        ProfileState(),
      ],
      verify: (_) =>
          verify(() => profileRepository.getProfile('user-id')).called(1),
    );

    blocTest<ProfileCubit, ProfileState>(
      'emits failure when loading fails',
      setUp: () =>
          when(() => profileRepository.getProfile(any()))
              .thenThrow(const GetProfileFailure()),
      build: buildCubit,
      act: (_) => userController.add(user),
      expect: () => const [
        ProfileState(status: ProfileStatus.loading),
        ProfileState(status: ProfileStatus.failure),
      ],
      errors: () => [isA<GetProfileFailure>()],
    );

    blocTest<ProfileCubit, ProfileState>(
      'emits failure when loading times out',
      setUp: () =>
          when(() => profileRepository.getProfile(any()))
              .thenAnswer((_) => Completer<Profile>().future),
      build: () => ProfileCubit(
        authRepository: authRepository,
        profileRepository: profileRepository,
        loadTimeout: const Duration(milliseconds: 10),
      ),
      act: (_) => userController.add(user),
      wait: const Duration(milliseconds: 50),
      expect: () => const [
        ProfileState(status: ProfileStatus.loading),
        ProfileState(status: ProfileStatus.failure),
      ],
      errors: () => [isA<TimeoutException>()],
    );

    test('times out after 15 seconds by default', () {
      expect(ProfileCubit.defaultLoadTimeout, const Duration(seconds: 15));
    });

    blocTest<ProfileCubit, ProfileState>(
      'drops a stale profile when the user changed meanwhile',
      setUp: () {
        final pending = Completer<Profile>();
        when(() => profileRepository.getProfile('user-id'))
            .thenAnswer((_) => pending.future);
        when(() => profileRepository.getProfile('other-id'))
            .thenAnswer((_) async {
              pending.complete(profile);
              return const Profile(id: 'other-id');
            });
      },
      build: buildCubit,
      act: (_) async {
        userController.add(user);
        await Future<void>.delayed(Duration.zero);
        userController.add(otherUser);
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => const [
        ProfileState(status: ProfileStatus.loading),
        ProfileState(
          status: ProfileStatus.success,
          profile: Profile(id: 'other-id'),
        ),
      ],
    );

    blocTest<ProfileCubit, ProfileState>(
      'drops a stale failure when the user signed out meanwhile',
      setUp: () {
        final pending = Completer<Profile>();
        when(() => profileRepository.getProfile(any()))
            .thenAnswer((_) => pending.future);
        addTearDown(() => pending.completeError(const GetProfileFailure()));
      },
      build: buildCubit,
      act: (_) async {
        userController.add(user);
        await Future<void>.delayed(Duration.zero);
        userController.add(null);
      },
      expect: () => const [
        ProfileState(status: ProfileStatus.loading),
        ProfileState(),
      ],
    );

    group('retry', () {
      blocTest<ProfileCubit, ProfileState>(
        'does nothing without a user',
        build: buildCubit,
        act: (cubit) => cubit.retry(),
        expect: () => const <ProfileState>[],
      );

      blocTest<ProfileCubit, ProfileState>(
        'loads the profile again',
        build: buildCubit,
        act: (cubit) async {
          userController.add(user);
          await Future<void>.delayed(Duration.zero);
          cubit.retry();
        },
        expect: () => const [
          ProfileState(status: ProfileStatus.loading),
          loadedState,
          ProfileState(status: ProfileStatus.loading),
          loadedState,
        ],
      );
    });

    group('profileUpdated', () {
      blocTest<ProfileCubit, ProfileState>(
        'shows the saved profile of the signed-in user only',
        build: buildCubit,
        act: (cubit) async {
          cubit.profileUpdated(profile);
          userController.add(user);
          await Future<void>.delayed(Duration.zero);
          cubit
            ..profileUpdated(const Profile(id: 'other'))
            ..profileUpdated(
              Profile(id: profile.id, firstName: 'Saved', role: profile.role),
            );
        },
        skip: 2,
        expect: () => [
          ProfileState(
            status: ProfileStatus.success,
            profile: Profile(
              id: profile.id,
              firstName: 'Saved',
              role: profile.role,
            ),
          ),
        ],
      );
    });

    group('selectRole', () {
      blocTest<ProfileCubit, ProfileState>(
        'does nothing without a profile',
        build: buildCubit,
        act: (cubit) => cubit.selectRole(UserRole.seller),
        expect: () => const <ProfileState>[],
        verify: (_) =>
            verifyNever(() => profileRepository.updateRole(any(), any())),
      );

      blocTest<ProfileCubit, ProfileState>(
        'saves the role and updates the profile',
        build: buildCubit,
        act: (cubit) async {
          userController.add(user);
          await Future<void>.delayed(Duration.zero);
          await cubit.selectRole(UserRole.buyer);
        },
        skip: 2,
        expect: () => const [
          ProfileState(
            status: ProfileStatus.success,
            profile: profile,
            roleUpdateStatus: RoleUpdateStatus.inProgress,
          ),
          ProfileState(
            status: ProfileStatus.success,
            profile: Profile(
              id: 'user-id',
              firstName: 'Jane',
              role: UserRole.buyer,
            ),
          ),
        ],
        verify: (_) => verify(
          () => profileRepository.updateRole('user-id', UserRole.buyer),
        ),
      );

      blocTest<ProfileCubit, ProfileState>(
        'ignores a second selection while saving',
        build: buildCubit,
        act: (cubit) async {
          userController.add(user);
          await Future<void>.delayed(Duration.zero);
          unawaited(cubit.selectRole(UserRole.buyer));
          await cubit.selectRole(UserRole.seller);
        },
        verify: (_) =>
            verify(() => profileRepository.updateRole(any(), any())).called(1),
      );

      blocTest<ProfileCubit, ProfileState>(
        'emits a role failure when saving fails',
        setUp: () =>
            when(() => profileRepository.updateRole(any(), any()))
                .thenThrow(const UpdateRoleFailure()),
        build: buildCubit,
        act: (cubit) async {
          userController.add(user);
          await Future<void>.delayed(Duration.zero);
          await cubit.selectRole(UserRole.seller);
        },
        skip: 2,
        expect: () => const [
          ProfileState(
            status: ProfileStatus.success,
            profile: profile,
            roleUpdateStatus: RoleUpdateStatus.inProgress,
          ),
          ProfileState(
            status: ProfileStatus.success,
            profile: profile,
            roleUpdateStatus: RoleUpdateStatus.failure,
          ),
        ],
        errors: () => [isA<UpdateRoleFailure>()],
      );

      blocTest<ProfileCubit, ProfileState>(
        'drops the result when the user signed out meanwhile',
        setUp: () {
          final pending = Completer<void>();
          when(() => profileRepository.updateRole(any(), any()))
              .thenAnswer((_) => pending.future);
          addTearDown(pending.complete);
        },
        build: buildCubit,
        act: (cubit) async {
          userController.add(user);
          await Future<void>.delayed(Duration.zero);
          final saving = cubit.selectRole(UserRole.seller);
          userController.add(null);
          await Future<void>.delayed(Duration.zero);
          expect(cubit.state, const ProfileState());
          unawaited(saving);
        },
        skip: 3,
        expect: () => const [ProfileState()],
      );
    });
  });
}
