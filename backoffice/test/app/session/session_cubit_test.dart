import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/helpers.dart';

void main() {
  late MockBackOfficeAuthRepository auth;
  late MockBackOfficeRepository repository;
  late StreamController<AuthState> changes;

  setUp(() {
    auth = MockBackOfficeAuthRepository();
    repository = MockBackOfficeRepository();
    changes = StreamController<AuthState>.broadcast();
    when(() => auth.changes).thenAnswer((_) => changes.stream);
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  tearDown(() => changes.close());

  SessionCubit build() => SessionCubit(auth: auth, repository: repository);

  blocTest<SessionCubit, SessionState>(
    'signed out without a session',
    setUp: () => when(() => auth.isSignedIn).thenReturn(false),
    build: build,
    act: (cubit) => cubit.refresh(),
    expect: () => [const SessionState(status: SessionStatus.signedOut)],
  );

  blocTest<SessionCubit, SessionState>(
    'asks for the code before anything else',
    setUp: () => when(
      () => auth.mfaStatus(),
    ).thenAnswer((_) async => const MfaStatus(passed: false, factorId: 'f1')),
    build: build,
    act: (cubit) => cubit.refresh(),
    expect: () => [
      const SessionState(
        status: SessionStatus.mfa,
        mfa: MfaStatus(passed: false, factorId: 'f1'),
      ),
    ],
    verify: (_) => verifyNever(() => repository.me()),
  );

  blocTest<SessionCubit, SessionState>(
    'ready for a member, denied otherwise',
    setUp: () {
      when(
        () => auth.mfaStatus(),
      ).thenAnswer((_) async => const MfaStatus(passed: true, factorId: 'f1'));
      var calls = 0;
      when(() => repository.me()).thenAnswer(
        (_) async =>
            calls++ == 0 ? adminMe : const StaffMe(userId: 'u', aal2: true),
      );
    },
    build: build,
    act: (cubit) async {
      await cubit.refresh();
      await cubit.refresh();
    },
    expect: () => [
      const SessionState(
        status: SessionStatus.ready,
        me: adminMe,
        mfa: MfaStatus(passed: true, factorId: 'f1'),
      ),
      const SessionState(
        status: SessionStatus.denied,
        me: StaffMe(userId: 'u', aal2: true),
        mfa: MfaStatus(passed: true, factorId: 'f1'),
      ),
    ],
  );

  blocTest<SessionCubit, SessionState>(
    'failed when the back-office cannot be reached',
    setUp: () => when(() => auth.mfaStatus()).thenThrow(Exception('offline')),
    build: build,
    act: (cubit) => cubit.refresh(),
    expect: () => [const SessionState(status: SessionStatus.failed)],
  );

  blocTest<SessionCubit, SessionState>(
    'auth changes refresh, token refreshes do not',
    setUp: () => when(() => auth.isSignedIn).thenReturn(false),
    build: build,
    act: (cubit) async {
      changes
        ..add(const AuthState(AuthChangeEvent.tokenRefreshed, null))
        ..add(const AuthState(AuthChangeEvent.signedOut, null));
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [const SessionState(status: SessionStatus.signedOut)],
  );

  blocTest<SessionCubit, SessionState>(
    'a refused access refreshes; other failures do not',
    setUp: () => when(() => auth.isSignedIn).thenReturn(false),
    build: build,
    act: (cubit) async {
      cubit
        ..onFailure(Exception('x'))
        ..onFailure(const BackOfficeFailure(BackOfficeFailureReason.forbidden))
        ..onFailure(
          const BackOfficeFailure(BackOfficeFailureReason.mfaRequired),
        );
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [const SessionState(status: SessionStatus.signedOut)],
  );

  blocTest<SessionCubit, SessionState>(
    'signOut, even when the server fails',
    setUp: () => when(() => auth.signOut()).thenThrow(Exception('x')),
    build: build,
    act: (cubit) => cubit.signOut(),
    expect: () => [const SessionState(status: SessionStatus.signedOut)],
  );
}
