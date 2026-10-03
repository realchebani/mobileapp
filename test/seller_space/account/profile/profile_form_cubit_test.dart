import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/account/profile/cubit/profile_form_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  const profile = Profile(id: 'user-id', firstName: 'Sophie');
  late MockProfileRepository repository;

  setUpAll(() => registerFallbackValue(const ProfileDetails()));
  setUp(() => repository = MockProfileRepository());

  ProfileFormCubit build() => ProfileFormCubit(
    profileRepository: repository,
    profile: profile,
    timeout: const Duration(milliseconds: 50),
  );

  group(ProfileFormCubit, () {
    test('edits, validates and saves', () async {
      const saved = Profile(
        id: 'user-id',
        firstName: 'Sophie',
        lastName: 'Durand',
        phone: '06 12 34 56 78',
        postalAddress: '1 rue',
      );
      when(() => repository.updateDetails(any(), any()))
          .thenAnswer((_) async => saved);
      final cubit = build();
      expect(cubit.state.isDirty, isFalse);
      cubit
        ..firstNameChanged('Sophie')
        ..lastNameChanged('Durand')
        ..phoneChanged('abc')
        ..postalAddressChanged('1 rue');
      expect(cubit.state.isDirty, isTrue);
      expect(cubit.state.phoneError, ProfileFieldError.invalidPhone);
      await cubit.save();
      expect(cubit.state.showErrors, isTrue);
      cubit.phoneChanged('06 12 34 56 78');
      await cubit.save();
      expect(cubit.state.profile, saved);
      expect(cubit.state.status, ProfileFormStatus.saved);
      expect(cubit.state.isDirty, isFalse);
      verify(
        () => repository.updateDetails(
          'user-id',
          const ProfileDetails(
            firstName: 'Sophie',
            lastName: 'Durand',
            phone: '06 12 34 56 78',
            postalAddress: '1 rue',
          ),
        ),
      ).called(1);
      await cubit.close();
    });

    test('too long texts', () {
      final cubit = build()
        ..firstNameChanged('a' * 101)
        ..lastNameChanged('b' * 101)
        ..postalAddressChanged('c' * 301);
      expect(cubit.state.firstNameError, ProfileFieldError.tooLong);
      expect(cubit.state.lastNameError, ProfileFieldError.tooLong);
      expect(cubit.state.postalAddressError, ProfileFieldError.tooLong);
      expect(cubit.state.isValid, isFalse);
      expect(cubit.state.props, hasLength(7));
    });

    test('a failure keeps the values; one save at a time', () async {
      final gate = Completer<Profile>();
      when(() => repository.updateDetails(any(), any()))
          .thenAnswer((_) => gate.future);
      final cubit = build()..lastNameChanged('Durand');
      final first = cubit.save();
      await cubit.save();
      verify(() => repository.updateDetails(any(), any())).called(1);
      gate.completeError(const UpdateProfileFailure());
      await first;
      expect(cubit.state.status, ProfileFormStatus.failure);
      expect(cubit.state.lastName, 'Durand');
      await cubit.close();
    });

    test('nothing is emitted once closed', () async {
      final ok = Completer<Profile>();
      when(() => repository.updateDetails(any(), any()))
          .thenAnswer((_) => ok.future);
      final cubit = build();
      final save = cubit.save();
      await cubit.close();
      ok.complete(profile);
      await save;

      final failing = Completer<Profile>();
      when(() => repository.updateDetails(any(), any()))
          .thenAnswer((_) => failing.future);
      final other = build();
      final saveOther = other.save();
      await other.close();
      failing.completeError(const UpdateProfileFailure());
      await saveOther;
    });
  });
}
