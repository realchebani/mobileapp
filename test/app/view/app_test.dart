import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/onboarding/onboarding.dart';
import 'package:mobileapp/role/role.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/splash/splash.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';

void main() {
  const user = AuthUser(id: 'user-id', email: 'jane@example.com');

  late AuthRepository authRepository;
  late ProfileRepository profileRepository;
  late PropertyRepository propertyRepository;
  late StreamController<AuthUser?> userController;

  setUpAll(() async {
    registerFallbackValue(UserRole.seller);
    registerFallbackValue(<String, Object?>{});
    await loadRealestyFonts();
  });

  setUp(() {
    usePhoneSurface();
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher
      ..localesTestValue = const [Locale('fr', 'FR')];
    addTearDown(dispatcher.clearLocalesTestValue);
    authRepository = MockAuthRepository();
    profileRepository = MockProfileRepository();
    propertyRepository = MockPropertyRepository();
    when(() => propertyRepository.getOrCreateDossier(any())).thenAnswer(
      (_) async => const Property(id: 'property-id', ownerId: 'user-id'),
    );
    when(() => propertyRepository.getOwners(any())).thenAnswer((_) async => []);
    when(() => propertyRepository.getParcels(any()))
        .thenAnswer((_) async => []);
    when(() => propertyRepository.getPreviousEstimates(any()))
        .thenAnswer((_) async => []);
    when(() => propertyRepository.getRooms(any())).thenAnswer((_) async => []);
    when(() => propertyRepository.getLifestyleItems(any()))
        .thenAnswer((_) async => []);
    when(() => propertyRepository.getDocuments(any()))
        .thenAnswer((_) async => []);
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
        propertyRepository: propertyRepository,
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

      // Signing out forgets the e-mail and the accepted terms.
      await emitUser(tester, null);
      await tester.tap(find.text('Continuer avec un e-mail'));
      await tester.pumpAndSettle();
      expect(find.text('jane@example.com'), findsNothing);
      expect(
        tester.widget<RealestyCheckbox>(find.byType(RealestyCheckbox)).value,
        isFalse,
      );
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
      expect(find.text('Mon dossier vendeur'), findsOneWidget);
      expect(find.text('Design system'), findsNothing);

      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginView), findsOneWidget);
    });

    testWidgets('walks a returning seller through the tunnel', (tester) async {
      when(() => profileRepository.getProfile(any())).thenAnswer(
        (_) async => const Profile(id: 'user-id', role: UserRole.seller),
      );
      when(() => propertyRepository.updateProperty(any(), any())).thenAnswer(
        (invocation) async => Property(
          id: 'property-id',
          ownerId: 'user-id',
          currentStep:
              (invocation.positionalArguments[1] as Map)['current_step'] as int,
        ),
      );
      when(() => propertyRepository.getOrCreateDossier(any())).thenAnswer(
        (_) async => const Property(
          id: 'property-id',
          ownerId: 'user-id',
          currentStep: 7,
        ),
      );
      await pumpApp(tester);
      await emitUser(tester, user);
      expect(find.byType(SellerHomePage), findsOneWidget);

      // Resumes at the last step (V1–V6 are covered by their own page tests).
      await tester.tap(find.text('Reprendre l’audit (étape 7/7)'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentsPage), findsOneWidget);

      await tester.tap(find.text('Envoyer mon dossier à l’expert'));
      await tester.pumpAndSettle();
      expect(find.byType(SubmittedPage), findsOneWidget);
      final patch =
          verify(
                () => propertyRepository.updateProperty(
                  'property-id',
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch['current_step'], 8);
      expect(patch['status'], PropertyStatus.submitted);

      await tester.tap(find.text('Retour à mon dossier'));
      await tester.pumpAndSettle();
      expect(find.text('Voir mon dossier envoyé'), findsOneWidget);

      await tester.tap(find.text('Voir mon dossier envoyé'));
      await tester.pumpAndSettle();
      expect(find.byType(SubmittedPage), findsOneWidget);
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
      expect(find.byType(SellerHomePage), findsOneWidget);

      await tester.tap(find.text('Design system'));
      await tester.pumpAndSettle();
      expect(find.byType(DesignSystemGalleryPage), findsOneWidget);
    });
  });
}
