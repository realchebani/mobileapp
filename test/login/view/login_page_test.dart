import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(loadRealestyFonts);

  late LoginCubit loginCubit;
  late MockGoRouter goRouter;

  const expired = LoginState(
    status: LoginStatus.failure,
    failureReason: LoginFailureReason.linkExpired,
  );
  const expiredMessage =
      'Ce lien a expiré ou a déjà été utilisé. Renvoyez-en un.';

  setUp(() {
    loginCubit = MockLoginCubit();
    when(() => loginCubit.state).thenReturn(const LoginState());
    goRouter = MockGoRouter();
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpApp(
    const LoginPage(),
    loginCubit: loginCubit,
    goRouter: goRouter,
  );

  group(LoginPage, () {
    testWidgets('renders the welcome and opens the e-mail login', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Bienvenue'), findsOneWidget);
      expect(find.textContaining('dossier audité par l’IA'), findsOneWidget);

      await tester.tap(find.text('Continuer avec un e-mail'));

      verify(loginCubit.editEmail).called(1);
      verify(() => goRouter.push<Object?>(AppRoutes.loginEmail)).called(1);
    });

    testWidgets('opens the e-mail login once on a double tap', (tester) async {
      final closed = Completer<Object?>();
      when(() => goRouter.push<Object?>(any()))
          .thenAnswer((_) => closed.future);
      await pump(tester);

      await tester.tap(find.text('Continuer avec un e-mail'));
      await tester.tap(find.text('Continuer avec un e-mail'));
      verify(() => goRouter.push<Object?>(AppRoutes.loginEmail)).called(1);

      closed.complete(null);
      await tester.pump();
      await tester.tap(find.text('Continuer avec un e-mail'));
      verify(() => goRouter.push<Object?>(AppRoutes.loginEmail)).called(1);
    });

    testWidgets('shows a link failure reported before it was shown', (
      tester,
    ) async {
      when(() => loginCubit.state).thenReturn(expired);
      await pump(tester);
      await tester.pump();

      expect(find.text(expiredMessage), findsOneWidget);
    });

    testWidgets('shows a link failure reported while shown', (tester) async {
      whenListen(
        loginCubit,
        Stream.fromIterable([expired]),
        initialState: const LoginState(),
      );
      await pump(tester);
      await tester.pump();

      expect(find.text(expiredMessage), findsOneWidget);
    });

    testWidgets('hides the test sign-in without credentials', (tester) async {
      await pump(tester);

      expect(find.byType(DevTestLoginButton), findsNothing);
      expect(find.text('Connexion de test (dev)'), findsNothing);
    });

    testWidgets('shows the test sign-in with credentials', (tester) async {
      await tester.pumpApp(
        const LoginView(
          devTestCredentials: DevTestCredentials(
            email: 'dev@example.com',
            password: 'secret',
          ),
        ),
        loginCubit: loginCubit,
        goRouter: goRouter,
      );

      expect(find.text('Connexion de test (dev)'), findsOneWidget);
    });

    testWidgets('ignores other failures', (tester) async {
      when(() => loginCubit.state).thenReturn(
        const LoginState(
          status: LoginStatus.failure,
          failureReason: LoginFailureReason.network,
        ),
      );
      await pump(tester);
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
