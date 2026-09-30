import 'package:auth_repository/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/bloc/app_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository;

void main() {
  const user = AuthUser(id: 'user-id', email: 'jane@example.com');

  late AuthRepository authRepository;

  setUp(() {
    authRepository = _MockAuthRepository();
  });

  AppBloc buildBloc() => AppBloc(authRepository: authRepository);

  group('AppBloc', () {
    test('initial state is unknown', () {
      expect(buildBloc().state, const AppState());
      expect(buildBloc().state.status, AppStatus.unknown);
    });

    group('AppUserSubscriptionRequested', () {
      blocTest<AppBloc, AppState>(
        'emits authenticated / unauthenticated as the user changes',
        setUp: () =>
            when(() => authRepository.user)
                .thenAnswer((_) => Stream.fromIterable([null, user, null])),
        build: buildBloc,
        act: (bloc) => bloc.add(const AppUserSubscriptionRequested()),
        expect: () => const [
          AppState.unauthenticated(),
          AppState.authenticated(user),
          AppState.unauthenticated(),
        ],
      );

      final error = Exception('oops');
      blocTest<AppBloc, AppState>(
        'adds stream errors without changing state',
        setUp: () =>
            when(() => authRepository.user)
                .thenAnswer((_) => Stream.error(error)),
        build: buildBloc,
        act: (bloc) => bloc.add(const AppUserSubscriptionRequested()),
        expect: () => const <AppState>[],
        errors: () => [error],
      );
    });

    group('AppLogoutPressed', () {
      blocTest<AppBloc, AppState>(
        'signs out',
        setUp: () =>
            when(() => authRepository.signOut()).thenAnswer((_) async {}),
        build: buildBloc,
        act: (bloc) => bloc.add(const AppLogoutPressed()),
        expect: () => const <AppState>[],
        verify: (_) => verify(() => authRepository.signOut()).called(1),
      );

      const failure = SignOutFailure();
      blocTest<AppBloc, AppState>(
        'adds SignOutFailure as an error',
        setUp: () => when(() => authRepository.signOut()).thenThrow(failure),
        build: buildBloc,
        act: (bloc) => bloc.add(const AppLogoutPressed()),
        expect: () => const <AppState>[],
        errors: () => [failure],
      );
    });
  });

  group('AppState', () {
    test('named constructors set status and user', () {
      expect(
        const AppState.authenticated(user),
        const AppState(status: AppStatus.authenticated, user: user),
      );
      expect(
        const AppState.unauthenticated(),
        const AppState(status: AppStatus.unauthenticated),
      );
    });
  });
}
