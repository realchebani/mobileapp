import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/account_deletion/account_deletion.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';

import '../helpers/helpers.dart';

void main() {
  late MockProfileRepository profiles;
  late MockAuthRepository auth;
  final due = DateTime.utc(2026, 11, 2);

  setUp(() {
    profiles = MockProfileRepository();
    auth = MockAuthRepository();
  });

  AccountDeletionCubit build() => AccountDeletionCubit(
    profileRepository: profiles,
    authRepository: auth,
    timeout: const Duration(milliseconds: 50),
  );

  group(AccountDeletionCubit, () {
    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'loads the blockers',
      setUp: () =>
          when(profiles.getDeletionBlockers)
              .thenAnswer((_) async => {AccountDeletionBlocker.activeSale}),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [
        const AccountDeletionState(status: AccountDeletionStatus.loading),
        const AccountDeletionState(
          status: AccountDeletionStatus.ready,
          blockers: {AccountDeletionBlocker.activeSale},
        ),
      ],
      verify: (cubit) => expect(cubit.state.isBlocked, isTrue),
    );

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'a failed load',
      setUp: () =>
          when(profiles.getDeletionBlockers)
              .thenThrow(const AccountDeletionFailure()),
      build: build,
      act: (cubit) => cubit.load(),
      errors: () => [isA<AccountDeletionFailure>()],
      verify: (cubit) =>
          expect(cubit.state.status, AccountDeletionStatus.loadFailure),
    );

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'needs the confirmation word, then deactivates',
      setUp: () =>
          when(profiles.deactivateAccount).thenAnswer((_) async => due),
      build: build,
      act: (cubit) async {
        await cubit.deactivate('SUPPRIMER');
        cubit.confirmationChanged(' supprimer ');
        await cubit.deactivate('SUPPRIMER');
      },
      expect: () => [
        const AccountDeletionState(showErrors: true),
        const AccountDeletionState(confirmation: ' supprimer '),
        const AccountDeletionState(
          confirmation: ' supprimer ',
          status: AccountDeletionStatus.deactivating,
        ),
        AccountDeletionState(
          confirmation: ' supprimer ',
          status: AccountDeletionStatus.deactivated,
          deletionDueAt: due,
        ),
      ],
    );

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'a refusal shows its blocker',
      setUp: () => when(profiles.deactivateAccount).thenThrow(
        const AccountDeletionFailure(
          blocker: AccountDeletionBlocker.staffAccount,
        ),
      ),
      build: build,
      seed: () => const AccountDeletionState(confirmation: 'SUPPRIMER'),
      act: (cubit) => cubit.deactivate('SUPPRIMER'),
      errors: () => [isA<AccountDeletionFailure>()],
      verify: (cubit) {
        expect(cubit.state.status, AccountDeletionStatus.ready);
        expect(cubit.state.blockers, {AccountDeletionBlocker.staffAccount});
      },
    );

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'a technical failure',
      setUp: () =>
          when(profiles.deactivateAccount)
              .thenThrow(const AccountDeletionFailure()),
      build: build,
      seed: () => const AccountDeletionState(confirmation: 'SUPPRIMER'),
      act: (cubit) => cubit.deactivate('SUPPRIMER'),
      errors: () => [isA<AccountDeletionFailure>()],
      verify: (cubit) =>
          expect(cubit.state.status, AccountDeletionStatus.deactivateFailure),
    );

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'a timeout',
      setUp: () =>
          when(profiles.deactivateAccount)
              .thenAnswer((_) => Completer<DateTime>().future),
      build: build,
      seed: () => const AccountDeletionState(confirmation: 'SUPPRIMER'),
      act: (cubit) => cubit.deactivate('SUPPRIMER'),
      wait: const Duration(milliseconds: 100),
      errors: () => [isA<TimeoutException>()],
      verify: (cubit) =>
          expect(cubit.state.status, AccountDeletionStatus.deactivateFailure),
    );

    test('one deactivation at a time; nothing once closed', () async {
      final gate = Completer<DateTime>();
      when(profiles.deactivateAccount).thenAnswer((_) => gate.future);
      final cubit = build()..confirmationChanged('SUPPRIMER');
      final first = cubit.deactivate('SUPPRIMER');
      await cubit.deactivate('SUPPRIMER');
      verify(profiles.deactivateAccount).called(1);
      await cubit.close();
      gate.complete(due);
      await first;

      for (final error in [const AccountDeletionFailure(), Exception('x')]) {
        final failing = Completer<DateTime>();
        when(profiles.deactivateAccount).thenAnswer((_) => failing.future);
        final other = build()..confirmationChanged('SUPPRIMER');
        final call = other.deactivate('SUPPRIMER');
        await other.close();
        failing.completeError(error);
        await call;
      }

      final blockers = Completer<Set<AccountDeletionBlocker>>();
      when(profiles.getDeletionBlockers).thenAnswer((_) => blockers.future);
      final loading = build();
      final load = loading.load();
      await loading.close();
      blockers.complete({});
      await load;

      final failingBlockers = Completer<Set<AccountDeletionBlocker>>();
      when(profiles.getDeletionBlockers)
          .thenAnswer((_) => failingBlockers.future);
      final failingLoad = build();
      final load2 = failingLoad.load();
      await failingLoad.close();
      failingBlockers.completeError(const AccountDeletionFailure());
      await load2;
    });

    test('finish signs out everywhere, else locally', () async {
      when(() => auth.signOut(everywhere: true)).thenAnswer((_) async {});
      await build().finish();
      verify(() => auth.signOut(everywhere: true)).called(1);

      when(() => auth.signOut(everywhere: true))
          .thenThrow(const SignOutFailure());
      when(auth.signOut).thenAnswer((_) async {});
      await build().finish();
      verify(auth.signOut).called(1);

      when(auth.signOut).thenThrow(const SignOutFailure());
      await build().finish();
    });

    test('state', () {
      expect(const AccountDeletionState().props, hasLength(5));
    });
  });
}
