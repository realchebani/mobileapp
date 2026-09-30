import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/home/home.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/onboarding/onboarding.dart';
import 'package:mobileapp/role/role.dart';
import 'package:mobileapp/splash/splash.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';

void main() {
  const user = AuthUser(id: 'user-id', email: 'jane@example.com');

  late AuthRepository authRepository;
  late ProfileRepository profileRepository;
  late StreamController<AuthUser?> userController;

  setUpAll(() async {
    registerFallbackValue(UserRole.seller);
    await loadRealestyFonts();
  });

  setUp(() {
    usePhoneSurface();
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher
      ..localesTestValue = const [Locale('fr', 'FR')];
    addTearDown(dispatcher.clearLocalesTestValue);
    authRepository = MockAuthRepository();
    profileRepository = MockProfileRepository();
    userController = StreamController<AuthUser?>.broadcast();
    when(() => authRepository.user).thenAnswer((_) => userController.stream);
    when(() => authRepository.linkFailures)
        .thenAnswer((_) => const Stream.empty());
    when(() => authRepository.sendMagicLink(email: any(named: 'email')))
        .thenAnswer((_) async {});
    when(authRepository.signOut).thenAnswer((_) async {
      userController.add(null);
    });
    when(() => profileRepository.getProfile(any()))
        .thenAnswer((_) async => const Profile(id: 'user-id'));
    when(() => profileRepository.updateRole(any(), any()))
        .thenAnswer((_) async {});
  });

  tearDown(() => userController.close());

  Future<void> pumpApp(
    WidgetTester tester, {
    bool onboardingSeen = true,
    bool? enableDesignSystem,
  }) async {
    SharedPreferences.setMockInitialValues({
      OnboardingRepository.seenKey: onboardingSeen,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      App(
        authRepository: authRepository,
        profileRepository: profileRepository,
        onboardingRepository: OnboardingRepository(preferences: preferences),
        enableDesignSystem: enableDesignSystem,
      ),
    );
  }

  Future<void> emitUser(WidgetTester tester, AuthUser? user) async {
    userController.add(user);
    await tester.pumpAndSettle();
  }

  group(App, () {
    testWidgets('shows the splash while the session is restored', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SplashView), findsOneWidget);
    });

    testWidgets('shows the onboarding on first launch, then the login', (
      tester,
    ) async {
      await pumpApp(tester, onboardingSeen: false);
      await emitUser(tester, null);
      expect(find.byType(OnboardingView), findsOneWidget);

      await tester.tap(find.text('Passer'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginView), findsOneWidget);
    });

    testWidgets('goes through the magic link login', (tester) async {
      await pumpApp(tester);
      await emitUser(tester, null);
      expect(find.byType(LoginView), findsOneWidget);

      await tester.tap(find.text('Continuer avec un e-mail'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginEmailView), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'jane@example.com');
      await tester.tapAt(
        tester.getTopLeft(find.byType(RealestyCheckbox)) + const Offset(11, 11),
      );
      await tester.pump();
      await tester.tap(find.text('Recevoir mon lien de connexion'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckInboxView), findsOneWidget);
      verify(() => authRepository.sendMagicLink(email: 'jane@example.com'))
          .called(1);

      await tester.tap(find.text('Changer d’adresse e-mail'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginEmailView), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);

      await tester.tap(find.text('Recevoir mon lien de connexion'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckInboxView), findsOneWidget);

      await emitUser(tester, user);
      expect(find.byType(RoleView), findsOneWidget);
      expect(find.byType(CheckInboxView), findsNothing);
    });

    testWidgets('lets a new user choose a role, then signs out', (
      tester,
    ) async {
      await pumpApp(tester);
      await emitUser(tester, user);
      expect(find.byType(RoleView), findsOneWidget);

      await tester.tap(find.text('Je souhaite vendre'));
      await tester.pumpAndSettle();
      verify(() => profileRepository.updateRole('user-id', UserRole.seller))
          .called(1);
      expect(find.text('Bienvenue dans votre espace vendeur'), findsOneWidget);
      expect(find.text('Design system'), findsNothing);

      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginView), findsOneWidget);
    });

    testWidgets('opens the space of a returning buyer', (tester) async {
      when(() => profileRepository.getProfile(any())).thenAnswer(
        (_) async => const Profile(id: 'user-id', role: UserRole.buyer),
      );
      await pumpApp(tester);
      await emitUser(tester, user);

      expect(find.text('Bienvenue dans votre espace acheteur'), findsOneWidget);
    });

    testWidgets('opens the design system gallery in development', (
      tester,
    ) async {
      when(() => profileRepository.getProfile(any())).thenAnswer(
        (_) async => const Profile(id: 'user-id', role: UserRole.seller),
      );
      await pumpApp(tester, enableDesignSystem: true);
      await emitUser(tester, user);
      expect(find.byType(HomePlaceholderPage), findsOneWidget);

      await tester.tap(find.text('Design system'));
      await tester.pumpAndSettle();
      expect(find.byType(DesignSystemGalleryPage), findsOneWidget);
    });
  });
}
