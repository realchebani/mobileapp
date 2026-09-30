import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(loadRealestyFonts);

  late LoginCubit loginCubit;
  late MockGoRouter goRouter;
  late List<Uri> openedUris;

  const sentState = LoginState(
    email: 'jane@example.com',
    termsAccepted: true,
    status: LoginStatus.sent,
    sentTo: 'jane@example.com',
    resendAvailableIn: 42,
  );

  setUp(() {
    usePhoneSurface();
    loginCubit = MockLoginCubit();
    when(() => loginCubit.state).thenReturn(sentState);
    goRouter = MockGoRouter();
    when(goRouter.canPop).thenReturn(true);
    openedUris = [];
  });

  Future<bool> openUrl(Uri uri) async {
    openedUris.add(uri);
    return true;
  }

  Future<void> pump(WidgetTester tester, {UrlOpener? opener}) => tester.pumpApp(
    CheckInboxPage(openUrl: opener ?? openUrl),
    loginCubit: loginCubit,
    goRouter: goRouter,
  );

  RealestyButton resendButton(WidgetTester tester) => tester.widget(
    find.ancestor(
      of: find.text('Renvoyer le lien'),
      matching: find.byType(RealestyButton),
    ),
  );

  group(CheckInboxPage, () {
    test('opens URLs with url_launcher by default', () {
      expect(const CheckInboxPage().openUrl, isNotNull);
    });

    testWidgets('renders the address in bold and the info banner', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
      final body = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.textSpan?.toPlainText().contains('jane@') ?? false),
        ),
      );
      final spans = (body.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans[1].text, 'jane@example.com');
      expect(spans[1].style!.fontWeight, FontWeight.w600);
      expect(find.byType(InlineBanner), findsOneWidget);
    });

    testWidgets('falls back to the entered e-mail, or plain text', (
      tester,
    ) async {
      when(() => loginCubit.state)
          .thenReturn(const LoginState(email: ' jane@example.com '));
      await pump(tester);
      expect(
        find.textContaining('à jane@example.com.', findRichText: true),
        findsOneWidget,
      );

      when(() => loginCubit.state).thenReturn(const LoginState());
      await pump(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('lien de connexion à .', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('shows the resend countdown as readable text', (tester) async {
      await pump(tester);

      expect(find.text('Renvoi possible dans 0:42'), findsOneWidget);
      expect(resendButton(tester).onPressed, isNull);
    });

    testWidgets('resends the link once the countdown is over', (tester) async {
      when(() => loginCubit.state)
          .thenReturn(sentState.copyWith(resendAvailableIn: 0));
      await pump(tester);

      expect(find.textContaining('Renvoi possible'), findsNothing);
      await tester.tap(find.text('Renvoyer le lien'));
      verify(loginCubit.resend).called(1);
    });

    testWidgets('shows a loading resend button while sending', (tester) async {
      when(() => loginCubit.state).thenReturn(
        sentState.copyWith(
          status: LoginStatus.submitting,
          resendAvailableIn: 0,
        ),
      );
      await pump(tester);

      final buttons = tester.widgetList<RealestyButton>(
        find.byType(RealestyButton),
      );
      expect(buttons.where((button) => button.isLoading), hasLength(1));
    });

    testWidgets('opens the Mail app', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Ouvrir Mail'));
      await tester.pump();

      expect(openedUris, [CheckInboxView.mailAppUri]);
      expect(find.text('Impossible d’ouvrir l’app Mail.'), findsNothing);
    });

    testWidgets('tells when Mail cannot be opened', (tester) async {
      await pump(tester, opener: (_) async => false);

      await tester.tap(find.text('Ouvrir Mail'));
      await tester.pump();

      expect(find.text('Impossible d’ouvrir l’app Mail.'), findsOneWidget);
    });

    testWidgets('tells when opening Mail throws', (tester) async {
      await pump(tester, opener: (_) => throw Exception('no handler'));

      await tester.tap(find.text('Ouvrir Mail'));
      await tester.pump();

      expect(find.text('Impossible d’ouvrir l’app Mail.'), findsOneWidget);
    });

    testWidgets('confirms a resent link', (tester) async {
      whenListen(
        loginCubit,
        Stream.fromIterable([
          sentState.copyWith(status: LoginStatus.submitting),
          sentState.copyWith(resendAvailableIn: 60),
        ]),
        initialState: sentState.copyWith(resendAvailableIn: 0),
      );
      await pump(tester);
      await tester.pump();

      expect(find.text('Nouveau lien envoyé.'), findsOneWidget);
    });

    testWidgets('shows link failures', (tester) async {
      whenListen(
        loginCubit,
        Stream.fromIterable([
          sentState.copyWith(
            status: LoginStatus.failure,
            failureReason: () => LoginFailureReason.linkExpired,
          ),
        ]),
        initialState: sentState,
      );
      await pump(tester);
      await tester.pump();

      expect(
        find.text('Ce lien a expiré ou a déjà été utilisé. Renvoyez-en un.'),
        findsOneWidget,
      );
    });

    testWidgets('shows unknown failures', (tester) async {
      whenListen(
        loginCubit,
        Stream.fromIterable([sentState.copyWith(status: LoginStatus.failure)]),
        initialState: sentState,
      );
      await pump(tester);
      await tester.pump();

      expect(find.text('Une erreur est survenue. Réessayez.'), findsOneWidget);
    });

    testWidgets('goes back from the back and "change address" buttons', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Retour'));
      await tester.tap(find.text('Changer d’adresse e-mail'));

      verify(() => goRouter.pop<Object?>()).called(2);
    });

    testWidgets('returns to the e-mail entry when popped', (tester) async {
      final router = GoRouter(
        initialLocation: '/verifier',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Text('home'),
            routes: [
              GoRoute(
                path: 'verifier',
                builder: (context, state) => CheckInboxPage(openUrl: openUrl),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpAppRouter(router, loginCubit: loginCubit);

      await tester.tap(find.text('Changer d’adresse e-mail'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      verify(loginCubit.editEmail).called(1);
    });
  });
}
