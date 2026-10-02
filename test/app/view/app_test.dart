import 'dart:async';
import 'dart:typed_data';

import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/onboarding/onboarding.dart';
import 'package:mobileapp/role/role.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/splash/splash.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';
import '../../seller_space/fixtures.dart';
import '../../seller_tunnel/steps/location/location_fixtures.dart';

/// The photo library, returning a small in-memory photo.
class _FakeImagePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(Uint8List(16), name: 'photo.jpg', path: 'photo.jpg');
}

/// The photo library of the walk: one photo.
class _FakePhotoLibrary implements PhotoLibrary {
  @override
  Future<List<Uint8List>> pick({required int limit}) async => [Uint8List(8)];
}

/// Photos ready to upload as they are.
class _FakePhotoProcessor implements PhotoProcessor {
  @override
  Future<ProcessedPhoto> process(
    Uint8List bytes, {
    double? tiltDegrees,
  }) async => ProcessedPhoto(
    bytes: bytes,
    width: 4,
    height: 3,
    quality: const PhotoQuality(),
  );

  @override
  Future<Uint8List> stripMetadata(Uint8List bytes) async => bytes;
}

/// Encodes a patch value as the database would store it.
Object? _encode(Object? value) => switch (value) {
  DbEnum() => value.value,
  DateTime() => value.toUtc().toIso8601String(),
  Iterable<Object?>() => [for (final item in value) _encode(item)],
  Map<String, Object?>() => {
    for (final MapEntry(:key, value: item) in value.entries) key: _encode(item),
  },
  _ => value,
};

/// [property] once [patch] is applied, as `updateProperty` returns it.
Property _patched(Property property, Map<String, Object?> patch) =>
    Property.fromJson({
      ...property.toJson(),
      for (final MapEntry(:key, :value) in patch.entries) key: _encode(value),
    });

void main() {
  const user = AuthUser(id: 'user-id', email: 'jane@example.com');

  late AuthRepository authRepository;
  late ProfileRepository profileRepository;
  late PropertyRepository propertyRepository;
  late ValuationRepository valuationRepository;
  late NotificationRepository notificationRepository;
  late Property dossier;
  late StreamController<AuthUser?> userController;

  setUpAll(() async {
    registerFallbackValue(UserRole.seller);
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(testPoint);
    registerFallbackValue(DocumentKind.other);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      const PropertyOwner(
        propertyId: 'p',
        position: 1,
        firstName: 'x',
        lastName: 'x',
      ),
    );
    registerFallbackValue(const PropertyParcel(propertyId: 'p', idu: 'x'));
    registerFallbackValue(const Room(propertyId: 'p', name: 'x', areaM2: 1));
    registerFallbackValue(
      const RoomPhoto(id: 'x', propertyId: 'p', roomId: 'r', storagePath: 's'),
    );
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
    valuationRepository = MockValuationRepository();
    notificationRepository = MockNotificationRepository();
    when(() => valuationRepository.getLatestValuation(any()))
        .thenAnswer((_) async => null);
    when(() => notificationRepository.getNotifications(any()))
        .thenAnswer((_) async => []);
    when(() => notificationRepository.markRead(any()))
        .thenAnswer((_) async => DateTime(2026));
    dossier = const Property(id: 'property-id', ownerId: 'user-id');
    when(() => propertyRepository.listProperties(any()))
        .thenAnswer((_) async => [dossier]);
    when(() => propertyRepository.listLots(any())).thenAnswer((_) async => []);
    when(() => propertyRepository.getProperty(any()))
        .thenAnswer((_) async => dossier);
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
    when(() => propertyRepository.getMarketSnapshot(any())).thenAnswer(
      (_) async => MarketSnapshot(
        id: 'snapshot-id',
        propertyId: 'property-id',
        status: MarketSnapshotStatus.ok,
        createdAt: DateTime(2026, 10),
        computedAt: DateTime(2026, 10),
        propertyType: PropertyType.house,
        livingAreaM2: 115,
        city: 'Chaponost',
        lowEur: 420000,
        medianEur: 479000,
        highEur: 546000,
        priceM2Low: 3572,
        priceM2Median: 4162,
        priceM2High: 4648,
        confidence: 79,
      ),
    );
    when(() => propertyRepository.requestEstimate(any()))
        .thenAnswer((_) async {});
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
    GeoRepository? geoRepository,
    PhotoServices Function(SharedPreferences preferences)? photoServices,
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
        valuationRepository: valuationRepository,
        notificationRepository: notificationRepository,
        geoRepository: geoRepository,
        photoServices: photoServices?.call(preferences),
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
      expect(find.byType(RealestyTabBar), findsOneWidget);

      // Signing out lives in the "Compte" tab.
      await tester.tap(find.text('Compte'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsOneWidget);
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
        (invocation) async => _patched(
          const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.house,
          ),
          invocation.positionalArguments[1] as Map<String, Object?>,
        ),
      );
      dossier = const Property(
        id: 'property-id',
        ownerId: 'user-id',
        propertyType: PropertyType.house,
        currentStep: 7,
      );
      when(() => propertyRepository.getDocuments(any())).thenAnswer(
        (_) async => [
          for (final kind in [
            DocumentKind.titleDeed,
            DocumentKind.identityDocument,
          ])
            PropertyDocument(
              id: kind.value,
              propertyId: 'property-id',
              kind: kind,
              storagePath: 'user-id/property-id/${kind.value}.pdf',
              fileName: '${kind.value}.pdf',
            ),
        ],
      );
      await pumpApp(tester);
      await emitUser(tester, user);
      expect(find.byType(SellerHomePage), findsOneWidget);

      // Resumes at the last step.
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
      // The non-certified estimate is requested once the dossier is sent.
      verify(() => propertyRepository.requestEstimate('property-id')).called(1);

      // V8 → V8b « Synthèse du marché » → back to V8.
      await tester.ensureVisible(find.text('Voir la synthèse du marché'));
      await tester.tap(find.text('Voir la synthèse du marché'));
      await tester.pumpAndSettle();
      expect(find.byType(MarketSynthesisPage), findsOneWidget);
      await tester.tap(find.text('Retour au suivi de mon dossier'));
      await tester.pumpAndSettle();
      expect(find.byType(SubmittedPage), findsOneWidget);

      // V8 → V9 (the tab bar is back), and V9 → V8 to follow the review.
      expect(find.byType(RealestyTabBar), findsNothing);
      await tester.tap(find.text('Aller au tableau de bord'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(RealestyTabBar), findsOneWidget);
      expect(find.text('Analyse en cours'), findsOneWidget);

      // V9 → V8b (its route exists now) → back to V9.
      await tester.ensureVisible(find.text('Voir la synthèse du marché'));
      await tester.tap(find.text('Voir la synthèse du marché'));
      await tester.pumpAndSettle();
      expect(find.byType(MarketSynthesisPage), findsOneWidget);
      expect(find.byType(RealestyTabBar), findsNothing);
      await tester.tap(find.text('Retour au suivi de mon dossier'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);

      await tester.ensureVisible(find.text('Suivi de mon dossier'));
      await tester.tap(find.text('Suivi de mon dossier'));
      await tester.pumpAndSettle();
      expect(find.byType(SubmittedPage), findsOneWidget);
    });

    testWidgets('walks a new seller through every step of the tunnel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1600);
      final geoRepository = MockGeoRepository();
      when(() => geoRepository.searchAddresses(any()))
          .thenAnswer((_) async => [testAddress]);
      when(() => geoRepository.parcelAt(any()))
          .thenAnswer((_) async => testParcel);
      when(geoRepository.close).thenReturn(null);
      when(() => profileRepository.getProfile(any())).thenAnswer(
        (_) async => const Profile(
          id: 'user-id',
          role: UserRole.seller,
          firstName: 'Jane',
        ),
      );
      // The dossier as stored: every patch is applied to it.
      var stored = const Property(id: 'property-id', ownerId: 'user-id');
      final patches = <Map<String, Object?>>[];
      when(() => propertyRepository.updateProperty(any(), any())).thenAnswer((
        invocation,
      ) async {
        final patch = invocation.positionalArguments[1] as Map<String, Object?>;
        patches.add(patch);
        return stored = _patched(stored, patch);
      });
      when(() => propertyRepository.saveOwner(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.single as PropertyOwner,
      );
      when(() => propertyRepository.saveParcel(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.single as PropertyParcel,
      );
      when(() => propertyRepository.saveRoom(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments.single as Room,
      );

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Finder field(String label) => find.descendant(
        of: find.widgetWithText(RealestyTextField, label).first,
        matching: find.byType(TextField),
      );

      Future<void> enter(String label, String text) async {
        await tester.ensureVisible(field(label));
        await tester.enterText(field(label), text);
        await tester.pump();
      }

      /// The last patch saved, which continued to [next].
      Map<String, Object?> continuedTo(SellerTunnelStep next) {
        expect(patches.last[PropertyColumns.currentStep], next.number);
        return patches.last;
      }

      await pumpApp(
        tester,
        geoRepository: geoRepository,
        photoServices: (preferences) => PhotoServices(
          preferences: PhotoPreferences(preferences: preferences),
          library: _FakePhotoLibrary(),
          processor: _FakePhotoProcessor(),
        ),
      );
      await emitUser(tester, user);
      await tap(find.text('Commencer l’audit'));

      // V1 · Propriétaires: the seller, prefilled from the profile.
      expect(find.byType(OwnersPage), findsOneWidget);
      await tap(find.text('Unique propriétaire'));
      await enter('Nom', 'Durand');
      await enter('Téléphone', '06 12 34 56 78');
      await tap(find.text('Continuer'));
      expect(find.byType(LocationPage), findsOneWidget);
      expect(
        continuedTo(SellerTunnelStep.location)[PropertyColumns.ownershipType],
        OwnershipType.single,
      );
      final owner =
          verify(() => propertyRepository.saveOwner(captureAny()))
                  .captured
                  .single
              as PropertyOwner;
      expect(owner.firstName, 'Jane');
      expect(owner.lastName, 'Durand');

      // V2 · Adresse & cadastre: a suggested address and its parcel.
      await tester.enterText(field('Adresse du bien'), '12 rue de la Col');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tap(find.text('12 rue de la Colombe'));
      await tap(find.text('Oui, c’est correct'));
      await tap(find.text('Aucune'));
      await tap(find.text('Continuer'));
      expect(find.byType(PropertyContextPage), findsOneWidget);
      final location = continuedTo(SellerTunnelStep.context);
      expect(location[PropertyColumns.addressBanId], testAddress.id);
      expect(location[PropertyColumns.parcelConfirmed], isTrue);
      verify(() => propertyRepository.saveParcel(any())).called(1);

      // V3 · Contexte.
      await tap(find.text('Maison'));
      await enter('Année d’achat', '2012');
      await tap(find.text('Non').first);
      await tap(find.text('Continuer'));
      expect(find.byType(TechnicalPage), findsOneWidget);
      expect(
        continuedTo(SellerTunnelStep.technical)[PropertyColumns.propertyType],
        PropertyType.house,
      );

      // V4b · Audit technique.
      await enter('Année de construction', '1998');
      await enter('Surface habitable', '100');
      await tap(find.text('R+1'));
      // Several heating systems (US-04.10).
      await tap(find.text('Électrique'));
      await tap(find.text('Poêle à granulés'));
      await tap(find.text('Enregistrer et continuer'));
      expect(find.byType(MethodPage), findsOneWidget);
      final technical = continuedTo(SellerTunnelStep.method);
      expect(technical[PropertyColumns.constructionYear], 1998);
      expect(technical[PropertyColumns.heatingSystems], [
        HeatingSystem.electricity,
        HeatingSystem.pellets,
      ]);

      // V5 · Méthode de relevé.
      await tap(find.text('Saisir manuellement'));
      expect(find.byType(SurfacesPage), findsOneWidget);
      expect(
        patches.last[PropertyColumns.measurementMethod],
        MeasurementMethod.manual,
      );

      // V5c · Surfaces: one room, a main one, with its photo (EPIC-15:
      // needed to send the dossier; the vision AI is declined).
      await tap(find.text('Ajouter une pièce'));
      await tap(find.text('Chambre'));
      await tester.enterText(field('Surface'), '12');
      await tap(find.text('Ajouter'));
      when(
        () => propertyRepository.getRoomPhotos(
          any(),
          roomId: any(named: 'roomId'),
        ),
      ).thenAnswer((_) async => []);
      when(() => propertyRepository.getPhotoUrls(any()))
          .thenAnswer((_) async => {});
      when(
        () => propertyRepository.uploadRoomPhoto(
          any(),
          bytes: any(named: 'bytes'),
        ),
      ).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.single as RoomPhoto,
      );
      await tap(find.bySemanticsLabel('Photos de Chambre 1\u00a0: aucune'));
      expect(find.byType(RoomPhotosPage), findsOneWidget);
      await tap(find.text('Photothèque'));
      expect(find.byType(PhotoConsentPage), findsOneWidget);
      await tap(find.text('Continuer sans l’IA'));
      await tap(find.text('Terminé'));
      expect(
        find.bySemanticsLabel('Photos de Chambre 1\u00a0: 1'),
        findsOneWidget,
      );
      await tap(find.text('C’est correct, continuer'));
      expect(find.byType(LifestylePage), findsOneWidget);
      expect(
        continuedTo(SellerTunnelStep.lifestyle)[PropertyColumns.livingAreaM2],
        12,
      );
      verify(() => propertyRepository.saveRoom(any())).called(1);

      // V6 · Cadre de vie: every question is optional.
      await tap(find.text('Continuer'));
      expect(find.byType(DocumentsPage), findsOneWidget);
      continuedTo(SellerTunnelStep.documents);

      // V7 · Documents: not sent without the title deed and the identity
      // document, which are imported from the photos (picker mocked; the
      // multi-page scan is tested with V7) and uploaded.
      await tap(find.text('Envoyer mon dossier à l’expert'));
      expect(find.byType(DocumentsPage), findsOneWidget);
      expect(
        find.text('Indispensable pour envoyer votre dossier'),
        findsNWidgets(2),
      );
      final previousPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _FakeImagePicker();
      addTearDown(() => ImagePickerPlatform.instance = previousPicker);
      final uploaded = <DocumentKind>[];
      when(
        () => propertyRepository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((invocation) async {
        final kind = invocation.namedArguments[#kind] as DocumentKind;
        uploaded.add(kind);
        return PropertyDocument(
          id: 'document-${kind.value}',
          propertyId: 'property-id',
          kind: kind,
          storagePath: 'user-id/property-id/${kind.value}.jpg',
          fileName: 'p.jpg',
        );
      });
      for (final kind in ['Titre de propriété', 'Pièce d’identité']) {
        final import = find.bySemanticsLabel('Importer · $kind');
        await tester.ensureVisible(import);
        await tester.pumpAndSettle();
        await tester.tap(import);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Photothèque'));
        await tester.pumpAndSettle();
      }
      expect(uploaded, [DocumentKind.titleDeed, DocumentKind.identityDocument]);
      expect(
        find.text('Indispensable pour envoyer votre dossier'),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tap(find.text('Envoyer mon dossier à l’expert'));
      expect(find.byType(SubmittedPage), findsOneWidget);
      expect(
        continuedTo(SellerTunnelStep.submitted)[PropertyColumns.status],
        PropertyStatus.submitted,
      );
      expect(stored.status, PropertyStatus.submitted);
      expect(stored.currentStep, 8);

      // The sent dossier can no longer be edited.
      GoRouter.of(tester.element(find.byType(SubmittedPage)))
          .go(SellerTunnelStep.technical.routeFor('property-id'));
      await tester.pumpAndSettle();
      expect(find.byType(SubmittedPage), findsOneWidget);
      expect(find.byType(TechnicalPage), findsNothing);
    });

    testWidgets('keeps a dossier taken over by the expert on V8', (
      tester,
    ) async {
      when(() => profileRepository.getProfile(any())).thenAnswer(
        (_) async => const Profile(id: 'user-id', role: UserRole.seller),
      );
      dossier = const Property(
        id: 'property-id',
        ownerId: 'user-id',
        status: PropertyStatus.inReview,
        currentStep: 8,
      );
      await pumpApp(tester);
      await emitUser(tester, user);
      expect(find.byType(DashboardPage), findsOneWidget);

      for (final step in SellerTunnelStep.values) {
        GoRouter.of(tester.element(find.byType(Navigator).first))
            .go(step.routeFor('property-id'));
        await tester.pumpAndSettle();
        expect(find.byType(SubmittedPage), findsOneWidget, reason: step.name);
      }
      verifyNever(() => propertyRepository.updateProperty(any(), any()));
    });

    testWidgets('lets a seller with several properties open each one', (
      tester,
    ) async {
      when(() => profileRepository.getProfile(any())).thenAnswer(
        (_) async => const Profile(id: 'user-id', role: UserRole.seller),
      );
      const house = Property(
        id: 'property-id',
        ownerId: 'user-id',
        propertyType: PropertyType.house,
        status: PropertyStatus.submitted,
        currentStep: 8,
        lotId: 'lot',
      );
      const garage = Property(
        id: 'garage-id',
        ownerId: 'user-id',
        propertyType: PropertyType.parking,
        lotId: 'lot',
      );
      when(() => propertyRepository.listProperties(any()))
          .thenAnswer((_) async => [house, garage]);
      when(() => propertyRepository.listLots(any())).thenAnswer(
        (_) async => const [PropertyLot(id: 'lot', ownerId: 'user-id')],
      );
      when(() => propertyRepository.getProperty(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments.first == 'garage-id'
            ? garage
            : house,
      );
      await pumpApp(tester);
      await emitUser(tester, user);
      expect(find.byType(MyPropertiesPage), findsOneWidget);

      GoRouter router() =>
          GoRouter.of(tester.element(find.byType(Navigator).first));

      router().go('/vendeur/biens/garage-id');
      await tester.pumpAndSettle();
      expect(find.byType(SellerHomePage), findsOneWidget);

      router().go('/vendeur/lots/lot');
      await tester.pumpAndSettle();
      expect(find.byType(LotPage), findsOneWidget);

      router().go('/vendeur/biens/nouveau');
      await tester.pumpAndSettle();
      expect(find.byType(NewPropertyPage), findsOneWidget);

      // Old links open the most recently updated property (here, the first).
      router().go('/vendeur/marche');
      await tester.pumpAndSettle();
      expect(find.byType(MarketSynthesisPage), findsOneWidget);
      router().go('/vendeur/audit/proprietaires');
      await tester.pumpAndSettle();
      expect(find.byType(SubmittedPage), findsOneWidget);

      router().go('/vendeur/compte');
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsOneWidget);
    });

    testWidgets('shows a certified seller the dashboard and the report', (
      tester,
    ) async {
      when(() => profileRepository.getProfile(any())).thenAnswer(
        (_) async => const Profile(
          id: 'user-id',
          role: UserRole.seller,
          firstName: 'Sophie',
        ),
      );
      dossier = certifiedProperty;
      when(() => valuationRepository.getLatestValuation(any()))
          .thenAnswer((_) async => testValuation);
      when(() => notificationRepository.getNotifications(any()))
          .thenAnswer((_) async => [testNotification]);
      await pumpApp(tester);
      await emitUser(tester, user);

      // V9 · certified variant, with an unread notification.
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('Sophie'), findsOneWidget);
      expect(find.text('525 000 €'), findsOneWidget);
      final bell = find.bySemanticsLabel('Notifications, 1 non lue');
      expect(bell, findsOneWidget);

      // The notification opens the report and is marked read.
      await tester.tap(bell);
      await tester.pumpAndSettle();
      await tester.tap(find.text(testNotification.title));
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);
      expect(find.byType(RealestyTabBar), findsOneWidget);
      verify(() => notificationRepository.markRead(['notification-id']))
          .called(1);

      await tester.tap(find.text('Prix'));
      await tester.pumpAndSettle();
      expect(find.text('Ce qui vous revient'), findsOneWidget);

      // Back to V9, then the other tabs.
      await tester.tap(find.bySemanticsLabel('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);
      await tester.tap(find.text('Visites'));
      await tester.pumpAndSettle();
      expect(find.text('Demandes de visite'), findsOneWidget);
      await tester.tap(find.text('Coffre-fort'));
      await tester.pumpAndSettle();
      expect(find.text('Bientôt'), findsOneWidget);
      // Each tab keeps its stack: Mon bien is still V9.
      await tester.tap(find.text('Mon bien'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);
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

      await tester.tap(find.text('Compte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Design system'));
      await tester.pumpAndSettle();
      expect(find.byType(DesignSystemGalleryPage), findsOneWidget);
    });
  });
}
