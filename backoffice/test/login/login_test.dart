import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/login/login.dart';

import '../helpers/helpers.dart';

void main() {
  late MockBackOfficeAuthRepository auth;

  setUp(() {
    auth = MockBackOfficeAuthRepository();
    when(() => auth.sendMagicLink(any(), redirectTo: any(named: 'redirectTo')))
        .thenAnswer((_) async {});
    when(() => auth.signInWithPassword(any(), any())).thenAnswer((_) async {});
  });

  group(LoginCubit, () {
    LoginCubit build() => LoginCubit(auth: auth, redirectUrl: 'http://x/');

    blocTest<LoginCubit, LoginState>(
      'refuses an invalid e-mail',
      build: build,
      act: (cubit) async {
        cubit.emailChanged('nope');
        await cubit.sendLink();
      },
      expect: () => [
        const LoginState(email: 'nope'),
        const LoginState(email: 'nope', status: LoginStatus.invalidEmail),
      ],
    );

    blocTest<LoginCubit, LoginState>(
      'sends the link with the redirect URL',
      build: build,
      act: (cubit) async {
        cubit.emailChanged(' a@b.fr ');
        await cubit.sendLink();
        cubit.restart();
      },
      expect: () => [
        const LoginState(email: ' a@b.fr '),
        const LoginState(email: ' a@b.fr ', status: LoginStatus.sending),
        const LoginState(email: ' a@b.fr ', status: LoginStatus.sent),
        const LoginState(email: ' a@b.fr '),
      ],
      verify: (_) =>
          verify(() => auth.sendMagicLink(' a@b.fr ', redirectTo: 'http://x/'))
              .called(1),
    );

    blocTest<LoginCubit, LoginState>(
      'rate limits and other failures',
      setUp: () {
        var calls = 0;
        when(
          () => auth.sendMagicLink(any(), redirectTo: any(named: 'redirectTo')),
        ).thenAnswer(
          (_) async => throw BackOfficeAuthFailure(
            calls++ == 0
                ? BackOfficeAuthFailureReason.rateLimited
                : BackOfficeAuthFailureReason.unknown,
          ),
        );
      },
      build: build,
      seed: () => const LoginState(email: 'a@b.fr'),
      act: (cubit) async {
        await cubit.sendLink();
        await cubit.sendLink();
      },
      skip: 1,
      expect: () => [
        const LoginState(email: 'a@b.fr', status: LoginStatus.rateLimited),
        const LoginState(email: 'a@b.fr', status: LoginStatus.sending),
        const LoginState(email: 'a@b.fr', status: LoginStatus.failure),
      ],
    );

    blocTest<LoginCubit, LoginState>(
      'password sign-in (development)',
      setUp: () {
        var calls = 0;
        when(() => auth.signInWithPassword(any(), any())).thenAnswer((_) async {
          if (calls++ > 0) {
            throw const BackOfficeAuthFailure(
              BackOfficeAuthFailureReason.unknown,
            );
          }
        });
      },
      build: build,
      act: (cubit) async {
        cubit
          ..emailChanged('a@b.fr')
          ..passwordChanged('pw');
        await cubit.signInWithPassword();
        await cubit.signInWithPassword();
      },
      skip: 2,
      expect: () => [
        const LoginState(
          email: 'a@b.fr',
          password: 'pw',
          status: LoginStatus.sending,
        ),
        const LoginState(email: 'a@b.fr', password: 'pw'),
        const LoginState(
          email: 'a@b.fr',
          password: 'pw',
          status: LoginStatus.sending,
        ),
        const LoginState(
          email: 'a@b.fr',
          password: 'pw',
          status: LoginStatus.passwordFailure,
        ),
      ],
    );
  });

  group(LoginPage, () {
    testWidgets('sends the link and shows the confirmation', (tester) async {
      tester.useDesktopSurface();
      await tester.pumpBo(const LoginPage(), auth: auth);
      expect(find.text('Connexion de l’équipe'), findsOneWidget);
      expect(find.text('Connexion de test (développement)'), findsNothing);
      await tester.tap(find.text('Recevoir le lien de connexion'));
      await tester.pump();
      expect(find.text('Adresse e-mail invalide'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'julien@realesty.fr');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Lien envoyé'), findsOneWidget);
      expect(find.textContaining('julien@realesty.fr'), findsOneWidget);
      await tester.tap(find.text('Utiliser une autre adresse'));
      await tester.pump();
      expect(find.text('Connexion de l’équipe'), findsOneWidget);
    });

    testWidgets('shows the errors and the dev sign-in', (tester) async {
      tester.useDesktopSurface();
      when(
        () => auth.sendMagicLink(any(), redirectTo: any(named: 'redirectTo')),
      ).thenThrow(
        const BackOfficeAuthFailure(BackOfficeAuthFailureReason.rateLimited),
      );
      when(() => auth.signInWithPassword(any(), any())).thenThrow(
        const BackOfficeAuthFailure(BackOfficeAuthFailureReason.unknown),
      );
      await tester.pumpBo(
        const LoginPage(),
        auth: auth,
        config: const BackOfficeConfig(
          authRedirectUrl: 'http://x/',
          devPasswordLogin: true,
        ),
      );
      await tester.enterText(find.byType(EditableText).first, 'a@b.fr');
      await tester.tap(find.text('Recevoir le lien de connexion'));
      await tester.pump();
      expect(find.textContaining('Trop de demandes'), findsOneWidget);
      when(
        () => auth.sendMagicLink(any(), redirectTo: any(named: 'redirectTo')),
      ).thenThrow(
        const BackOfficeAuthFailure(BackOfficeAuthFailureReason.unknown),
      );
      await tester.tap(find.text('Recevoir le lien de connexion'));
      await tester.pump();
      expect(find.text('L’envoi a échoué. Réessayez.'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, 'pw');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      expect(find.text('Identifiants refusés.'), findsOneWidget);
    });
  });
}
