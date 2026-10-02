import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/ai_estimate_card.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';
import '../pump_seller_space.dart';

void main() {
  late MockGoRouter goRouter;

  setUpAll(loadRealestyFonts);

  setUp(() {
    usePhoneSurface();
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  const owner = PropertyOwner(
    propertyId: 'property-id',
    position: 1,
    firstName: 'Sophie',
    lastName: 'Durand',
  );

  SellerTunnelState pending(PropertyStatus status, {bool estimate = true}) =>
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        owners: const [owner],
        property: Property(
          id: 'property-id',
          ownerId: 'user-id',
          status: status,
          propertyType: PropertyType.house,
          livingAreaM2: 115,
          aiEstimateLowEur: estimate ? 505000 : null,
          aiEstimateMedianEur: estimate ? 518000 : null,
          aiEstimateHighEur: estimate ? 545000 : null,
        ),
      );

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200);
    await tester.pumpAndSettle();
  }

  group('pending', () {
    testWidgets('submitted: AI trend, market link and follow-up', (
      tester,
    ) async {
      await tester.pumpSellerSpacePage(
        const DashboardPage(marketSynthesisAvailable: true),
        sellerTunnelCubit: mockSellerTunnelCubit(
          pending(PropertyStatus.submitted),
        ),
        goRouter: goRouter,
      );
      // The owner's first name when the profile has none.
      expect(find.text('Sophie'), findsOneWidget);
      expect(find.textContaining('entre les mains de notre expert'), findsOne);
      expect(find.text('Maison · 115 m²'), findsOneWidget);
      expect(find.text('Analyse en cours'), findsOneWidget);
      expect(find.byType(AiEstimateCard), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);

      await scrollTo(tester, find.text('Voir la synthèse du marché'));
      await tester.tap(find.text('Voir la synthèse du marché'));
      verify(() => goRouter.push<Object?>(AppRoutes.sellerMarket)).called(1);

      await scrollTo(tester, find.text('Suivi de mon dossier'));
      expect(find.text('Réponse estimée sous 24 h'), findsOneWidget);
      await tester.tap(find.text('Suivi de mon dossier'));
      verify(() => goRouter.go(AppRoutes.sellerSubmitted)).called(1);
    });

    testWidgets('in review without estimate nor market route', (tester) async {
      await tester.pumpSellerSpacePage(
        const DashboardPage(),
        sellerTunnelCubit: mockSellerTunnelCubit(
          pending(PropertyStatus.inReview, estimate: false),
        ),
        goRouter: goRouter,
      );
      expect(find.textContaining('Un expert analyse votre dossier.'), findsOne);
      expect(find.textContaining('tendance IA n’est pas disponible'), findsOne);
      expect(find.text('Voir la synthèse du marché'), findsNothing);
      await scrollTo(tester, find.text('Suivi de mon dossier'));
      expect(find.text('Un expert analyse votre dossier'), findsOneWidget);
    });
  });

  group('certified', () {
    testWidgets('value card, sale action and dossier card', (tester) async {
      final profileCubit = MockProfileCubit();
      when(() => profileCubit.state).thenReturn(
        const ProfileState(
          profile: Profile(id: 'user-id', firstName: 'Léa'),
        ),
      );
      await tester.pumpSellerSpacePage(
        const DashboardPage(marketSynthesisAvailable: false),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: certifiedProperty,
            rooms: testRooms,
            lifestyleItems: [
              LifestyleItem(
                propertyId: 'property-id',
                kind: LifestyleItemKind.asset,
                label: 'Calme',
              ),
              LifestyleItem(
                propertyId: 'property-id',
                kind: LifestyleItemKind.watchPoint,
                label: 'Route',
              ),
            ],
            documents: [
              PropertyDocument(
                id: 'd1',
                propertyId: 'property-id',
                kind: DocumentKind.titleDeed,
                storagePath: 'a',
                status: DocumentStatus.rejected,
              ),
            ],
          ),
        ),
        valuationCubit: mockValuationCubit(
          ValuationState(
            status: ValuationStatus.success,
            valuation: testValuation,
          ),
        ),
        notificationsCubit: mockNotificationsCubit(
          NotificationsState(notifications: [testNotification]),
        ),
        profileCubit: profileCubit,
        goRouter: goRouter,
      );
      expect(find.text('Léa'), findsOneWidget);
      expect(find.text('Rapport disponible'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications, 1 non lue'), findsOne);
      expect(find.text('525 000 €'), findsOneWidget);
      expect(
        find.text(
          'Fourchette 505 000 – 545 000 € · '
          'Tendance IA initiale 518 000 €',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Validé par Julien M., expert immobilier · 25/09/2026'),
        findsOneWidget,
      );

      await tester.tap(find.text('Voir le rapport complet'));
      verify(() => goRouter.go(AppRoutes.sellerReport)).called(1);

      await scrollTo(tester, find.text('Mettre mon bien en vente'));
      await tester.tap(find.text('Mettre mon bien en vente'));
      await tester.pump();
      expect(find.textContaining('arrive bientôt'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Cadre de vie'));
      expect(find.text('92 %'), findsOneWidget);
      expect(find.text('1 document · 1 à remplacer'), findsOneWidget);
      expect(find.text('Action requise'), findsOneWidget);
      expect(find.text('115 m² · 4 pièces'), findsOneWidget);
      expect(find.text('1 atout · 1 point de vigilance'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      expect(find.text('Aperçu de mes données'), findsOneWidget);
    });

    testWidgets('loading, failure and missing valuation', (tester) async {
      final loading = mockValuationCubit();
      await tester.pumpSellerSpacePage(
        const DashboardPage(),
        valuationCubit: loading,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final failed = mockValuationCubit(
        const ValuationState(status: ValuationStatus.failure),
      );
      await tester.pumpSellerSpacePage(
        const DashboardPage(),
        valuationCubit: failed,
      );
      expect(
        find.text('Impossible de charger votre avis de valeur.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Réessayer'));
      verify(() => failed.load('property-id')).called(1);

      await tester.pumpSellerSpacePage(
        const DashboardPage(),
        valuationCubit: mockValuationCubit(
          const ValuationState(status: ValuationStatus.success),
        ),
      );
      expect(
        find.text('Votre avis de valeur n’est pas encore disponible.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('CertifiedValueCard derives the expert initials', (tester) async {
    await tester.pumpApp(
      CertifiedValueCard(
        valuation: Valuation(
          id: 'v',
          propertyId: 'p',
          valueEur: 1000,
          lowEur: 1000,
          highEur: 1000,
          expertDisplayName: 'Anne Expert',
          certifiedAt: DateTime(2026, 9, 25),
          validUntil: DateTime(2026, 12, 25),
        ),
        onOpen: () {},
      ),
    );
    expect(find.text('AE'), findsOneWidget);
    expect(find.textContaining('Tendance IA'), findsNothing);
  });

  testWidgets('labels several unread notifications', (tester) async {
    await tester.pumpSellerSpacePage(
      const DashboardPage(),
      notificationsCubit: mockNotificationsCubit(
        NotificationsState(
          notifications: [
            testNotification,
            AppNotification(
              id: 'other',
              kind: AppNotificationKind.reviewStarted,
              title: 'Un expert analyse votre dossier',
              createdAt: DateTime(2026, 9, 24),
            ),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Notifications, 2 non lues'), findsOne);
  });

  group('back to the foreground', () {
    testWidgets('reloads silently', (tester) async {
      final tunnel = mockSellerTunnelCubit(certifiedState);
      when(tunnel.refresh).thenThrow(const PropertyLoadFailure());
      final valuation = mockValuationCubit(
        ValuationState(
          status: ValuationStatus.success,
          valuation: testValuation,
        ),
      );
      final notifications = mockNotificationsCubit();
      await tester.pumpSellerSpacePage(
        const DashboardPage(),
        sellerTunnelCubit: tunnel,
        valuationCubit: valuation,
        notificationsCubit: notifications,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      verify(tunnel.refresh).called(1);
      verify(notifications.load).called(1);
      verify(() => valuation.load('property-id')).called(1);
      // No error snackbar for a background reload.
      expect(find.textContaining('Impossible d’actualiser'), findsNothing);

      // Not after the page is gone.
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      verifyNever(tunnel.refresh);
    });
  });

  group('pull to refresh', () {
    testWidgets('reloads everything and reports a failure', (tester) async {
      final tunnel = mockSellerTunnelCubit(certifiedState);
      when(tunnel.refresh).thenThrow(const PropertyLoadFailure());
      final valuation = mockValuationCubit(
        ValuationState(
          status: ValuationStatus.success,
          valuation: testValuation,
        ),
      );
      final notifications = mockNotificationsCubit();
      await tester.pumpSellerSpacePage(
        const DashboardPage(),
        sellerTunnelCubit: tunnel,
        valuationCubit: valuation,
        notificationsCubit: notifications,
      );
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      verify(tunnel.refresh).called(1);
      verify(notifications.load).called(1);
      verify(() => valuation.load('property-id')).called(1);
      expect(find.textContaining('Impossible d’actualiser'), findsOneWidget);
    });

    testWidgets('a pending dossier has no valuation to reload', (tester) async {
      final tunnel = mockSellerTunnelCubit(pending(PropertyStatus.submitted));
      when(tunnel.refresh).thenAnswer((_) async {});
      final valuation = mockValuationCubit();
      await tester.pumpSellerSpacePage(
        const DashboardPage(marketSynthesisAvailable: false),
        sellerTunnelCubit: tunnel,
        valuationCubit: valuation,
      );
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      verify(tunnel.refresh).called(1);
      verifyNever(() => valuation.load(any()));
      expect(find.textContaining('Impossible d’actualiser'), findsNothing);
    });
  });
}
