import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(loadRealestyFonts);

  const email = 'dev@example.com';
  const password = 'secret';
  const credentials = DevTestCredentials(email: email, password: password);
  const buttonLabel = 'Connexion de test (dev)';

  group('DevTestCredentials', () {
    test('resolves only in the development flavor with both values', () {
      final resolved = DevTestCredentials.resolve(
        flavor: 'development',
        email: email,
        password: password,
      );
      expect(resolved?.email, email);
      expect(resolved?.password, password);

      for (final (flavor, e, p) in [
        ('staging', email, password),
        ('production', email, password),
        (null, email, password),
        ('development', '', password),
        ('development', email, ''),
      ]) {
        expect(
          DevTestCredentials.resolve(flavor: flavor, email: e, password: p),
          isNull,
        );
      }
    });

    test('is unavailable in tests (no flavor, no defines)', () {
      expect(DevTestCredentials.fromEnvironment, isNull);
    });
  });

  group(DevTestLoginButton, () {
    late MockAuthRepository authRepository;

    When<Future<void>> stubSignIn() => when(
      () => authRepository.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    );

    setUp(() {
      authRepository = MockAuthRepository();
      when(() => authRepository.linkFailures)
          .thenAnswer((_) => const Stream.empty());
    });

    Future<void> pump(WidgetTester tester) => tester.pumpApp(
      const Scaffold(body: DevTestLoginButton(credentials: credentials)),
      authRepository: authRepository,
    );

    testWidgets('signs in with the credentials, showing a spinner', (
      tester,
    ) async {
      final signIn = Completer<void>();
      stubSignIn().thenAnswer((_) => signIn.future);
      await pump(tester);

      await tester.tap(find.text(buttonLabel));
      await tester.pump();

      verify(
        () =>
            authRepository.signInWithPassword(email: email, password: password),
      ).called(1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(buttonLabel), findsNothing);

      // Blocked while signing in.
      await tester.tap(find.byType(TextButton));
      verifyNever(
        () => authRepository.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );

      signIn.complete();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    for (final (reason, message) in [
      (
        SignInWithPasswordFailureReason.invalidCredentials,
        'Identifiants de test refusés. '
            'Vérifiez config/development.local.json.',
      ),
      (
        SignInWithPasswordFailureReason.network,
        'Connexion impossible. Vérifiez votre accès à Internet et réessayez.',
      ),
      (
        SignInWithPasswordFailureReason.unknown,
        'Une erreur est survenue. Réessayez.',
      ),
    ]) {
      testWidgets('shows an error on failure ($reason)', (tester) async {
        stubSignIn().thenThrow(SignInWithPasswordFailure(reason));
        await pump(tester);

        await tester.tap(find.text(buttonLabel));
        await tester.pump();

        expect(find.text(message), findsOneWidget);
        expect(find.text(buttonLabel), findsOneWidget);
      });
    }

    testWidgets('ignores a failure once disposed', (tester) async {
      final signIn = Completer<void>();
      stubSignIn().thenAnswer((_) => signIn.future);
      await pump(tester);

      await tester.tap(find.text(buttonLabel));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());

      signIn.completeError(
        const SignInWithPasswordFailure(
          SignInWithPasswordFailureReason.network,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
