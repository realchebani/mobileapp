import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(loadRealestyFonts);

  late LoginCubit loginCubit;
  late MockGoRouter goRouter;

  const validState = LoginState(email: 'jane@example.com', termsAccepted: true);

  setUp(() {
    loginCubit = MockLoginCubit();
    when(() => loginCubit.state).thenReturn(const LoginState());
    goRouter = MockGoRouter();
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpApp(
    const LoginEmailPage(),
    loginCubit: loginCubit,
    goRouter: goRouter,
  );

  RealestyButton submitButton(WidgetTester tester) =>
      tester.widget(find.byType(RealestyButton));

  group(LoginEmailPage, () {
    testWidgets('renders the form, prefilled with the entered e-mail', (
      tester,
    ) async {
      when(() => loginCubit.state)
          .thenReturn(const LoginState(email: 'jane@example.com'));
      await pump(tester);

      expect(find.text('Connexion par e-mail'), findsOneWidget);
      expect(find.text('Adresse e-mail'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('forwards e-mail changes and terms toggles', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'jane@example.com');
      verify(() => loginCubit.emailChanged('jane@example.com')).called(1);

      await tester.tapAt(
        tester.getTopLeft(find.byType(RealestyCheckbox)) + const Offset(11, 11),
      );
      verify(loginCubit.termsToggled).called(1);
    });

    testWidgets('shows "coming soon" for the terms links', (tester) async {
      await pump(tester);

      await tester.tapOnText(
        find.textRange.ofSubstring('conditions d’utilisation'),
      );
      await tester.pump();
      expect(find.text('Bientôt disponible'), findsOneWidget);

      await tester.tapOnText(
        find.textRange.ofSubstring('politique de confidentialité'),
      );
      await tester.pump();
      expect(find.text('Bientôt disponible'), findsWidgets);
      verifyNever(loginCubit.termsToggled);
    });

    testWidgets('submits a valid form', (tester) async {
      when(() => loginCubit.state).thenReturn(validState);
      await pump(tester);

      await tester.tap(find.text('Recevoir mon lien de connexion'));
      verify(loginCubit.submit).called(1);
    });

    testWidgets('submits from the keyboard when the e-mail is valid', (
      tester,
    ) async {
      when(() => loginCubit.state).thenReturn(validState);
      await pump(tester);

      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      verify(loginCubit.submit).called(1);
    });

    testWidgets('shows a format error when validating an invalid e-mail', (
      tester,
    ) async {
      when(() => loginCubit.state).thenReturn(const LoginState(email: 'jane@'));
      await pump(tester);
      expect(find.text('Saisissez une adresse e-mail valide.'), findsNothing);

      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
      verifyNever(loginCubit.submit);
    });

    testWidgets('shows the server e-mail error in the field', (tester) async {
      when(() => loginCubit.state).thenReturn(
        const LoginState(
          email: 'jane@example.com',
          status: LoginStatus.failure,
          failureReason: LoginFailureReason.invalidEmail,
        ),
      );
      await pump(tester);

      expect(
        find.text('Cette adresse e-mail n’est pas valide.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a loading button while sending', (tester) async {
      when(() => loginCubit.state)
          .thenReturn(validState.copyWith(status: LoginStatus.submitting));
      await pump(tester);

      expect(submitButton(tester).isLoading, isTrue);
    });

    testWidgets('shows send failures in a snackbar', (tester) async {
      whenListen(
        loginCubit,
        Stream.fromIterable([
          validState.copyWith(status: LoginStatus.submitting),
          validState.copyWith(
            status: LoginStatus.failure,
            failureReason: () => LoginFailureReason.notAuthorized,
          ),
        ]),
        initialState: validState,
      );
      await pump(tester);
      await tester.pump();

      expect(
        find.text(
          'Cette adresse n’est pas autorisée pour le moment (version de test).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('opens "check your inbox" once the link is sent', (
      tester,
    ) async {
      whenListen(
        loginCubit,
        Stream.fromIterable([
          validState.copyWith(status: LoginStatus.submitting),
          validState.copyWith(
            status: LoginStatus.sent,
            sentTo: () => 'jane@example.com',
          ),
        ]),
        initialState: validState,
      );
      await pump(tester);
      await tester.pump();

      verify(() => goRouter.push<Object?>(AppRoutes.checkInbox)).called(1);
    });

    testWidgets('goes back', (tester) async {
      when(goRouter.canPop).thenReturn(true);
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.pop<Object?>()).called(1);
    });
  });
}
