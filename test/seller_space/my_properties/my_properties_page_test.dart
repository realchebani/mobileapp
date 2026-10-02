import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/my_properties/widgets/property_row.dart';
import 'package:mobileapp/seller_space/notifications/notifications_bell.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../pump_seller_space.dart';

void main() {
  const ownerId = 'user-id';
  const house = Property(
    id: 'house',
    ownerId: ownerId,
    propertyType: PropertyType.house,
    addressCity: 'Chaponost',
    status: PropertyStatus.certified,
    lotId: 'lot',
    aiEstimateLowEur: 300000,
    aiEstimateMedianEur: 320000,
    aiEstimateHighEur: 340000,
  );
  const land = Property(
    id: 'land',
    ownerId: ownerId,
    propertyType: PropertyType.land,
    lotId: 'lot',
  );
  const garage = Property(
    id: 'garage',
    ownerId: ownerId,
    propertyType: PropertyType.parking,
    currentStep: 3,
  );
  const cellar = Property(
    id: 'cellar',
    ownerId: ownerId,
    propertyType: PropertyType.outbuilding,
  );
  const lot = PropertyLot(
    id: 'lot',
    ownerId: ownerId,
    name: 'Maison + terrain',
  );

  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  Future<MockSellerPropertiesCubit> pump(
    WidgetTester tester, {
    List<Property> properties = const [house, land, garage, cellar],
    List<PropertyLot> lots = const [lot],
    NotificationsCubit? notificationsCubit,
  }) async {
    usePhoneSurface();
    final cubit = mockSellerPropertiesCubit(properties: properties, lots: lots);
    await tester.pumpSellerSpacePage(
      const MyPropertiesPage(),
      sellerPropertiesCubit: cubit,
      notificationsCubit: notificationsCubit,
      goRouter: goRouter,
    );
    return cubit;
  }

  group(MyPropertiesPage, () {
    testWidgets('lists the lots, then the other properties', (tester) async {
      await pump(
        tester,
        notificationsCubit: mockNotificationsCubit(
          NotificationsState(
            notifications: [
              AppNotification(
                id: 'n',
                kind: AppNotificationKind.valuationCertified,
                title: 'Certifié',
                propertyId: 'garage',
                createdAt: DateTime(2026),
              ),
            ],
          ),
        ),
      );
      expect(find.text('Mes biens'), findsOneWidget);
      expect(find.text('4 biens'), findsOneWidget);
      expect(find.text('LOTS DE VENTE'), findsOneWidget);
      expect(find.text('Maison + terrain'), findsOneWidget);
      expect(find.text('Maison · Chaponost'), findsOneWidget);
      expect(find.text('Certifié'), findsOneWidget);
      expect(find.text('Brouillon · étape 3/5'), findsOneWidget);
      // The bell and the row of the garage.
      expect(find.byType(UnreadDot), findsNWidgets(2));

      await tester.tap(find.text('Maison + terrain'));
      verify(() => goRouter.go('/vendeur/lots/lot')).called(1);
      await tester.tap(find.text('Garage / parking'));
      verify(() => goRouter.go('/vendeur/biens/garage')).called(1);
      await tester.ensureVisible(find.text('Ajouter un bien'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un bien').hitTestable());
      verify(() => goRouter.push<Object?>('/vendeur/biens/nouveau')).called(1);
      await tester.ensureVisible(find.text('Regrouper des biens en lot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regrouper des biens en lot').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Regrouper en lot'), findsOneWidget);
    });

    testWidgets('stops at the limit of the test phase', (tester) async {
      await pump(
        tester,
        properties: [
          for (var i = 0; i < PropertyRepository.maxProperties; i++)
            Property(id: 'p$i', ownerId: ownerId),
        ],
        lots: const [],
      );
      expect(
        find.text(
          'Vous avez atteint la limite de 5 biens pendant la phase de test.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ajouter un bien'), findsNothing);
    });

    testWidgets('pull to refresh reloads, and tells when it failed', (
      tester,
    ) async {
      final cubit = await pump(tester);
      when(cubit.refresh).thenAnswer((_) async => throw Exception('offline'));
      await tester.fling(find.text('Mes biens'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      verify(cubit.refresh).called(1);
      expect(find.text('Impossible d’actualiser vos biens.'), findsOneWidget);
    });

    testWidgets('pull to refresh without error', (tester) async {
      final cubit = await pump(tester);
      await tester.fling(find.text('Mes biens'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      verify(cubit.refresh).called(1);
      expect(find.text('Impossible d’actualiser vos biens.'), findsNothing);
    });

    testWidgets('a lot without property shows its card only', (tester) async {
      await pump(tester, properties: const [garage, cellar]);
      expect(find.text('Maison + terrain'), findsOneWidget);
    });
  });

  group(PropertyRow, () {
    testWidgets('deletes a draft after confirmation', (tester) async {
      final cubit = await pump(
        tester,
        properties: const [garage, cellar],
        lots: const [],
      );
      when(() => cubit.deleteProperty(garage)).thenAnswer((_) async {});
      final cubits = tester
          .element(find.byType(MyPropertiesPage))
          .read<SellerTunnelCubits>();

      await tester.tap(find.bySemanticsLabel('Supprimer le brouillon').first);
      await tester.pump();
      expect(
        find.text('Le bien et ses documents seront supprimés définitivement.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pump();
      expect(find.text('Annuler'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Supprimer le brouillon').first);
      await tester.pump();
      await tester.tap(find.text('Supprimer'));
      await tester.pump();
      await tester.pump();
      verify(() => cubit.deleteProperty(garage)).called(1);
      verify(() => cubits.forget('garage')).called(1);
    });

    testWidgets('tells when the deletion failed', (tester) async {
      final cubit = await pump(tester);
      when(() => cubit.deleteProperty(any()))
          .thenAnswer((_) async => throw const PropertyDeleteFailure());
      await tester.tap(find.bySemanticsLabel('Supprimer le brouillon').first);
      await tester.pump();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le bien n’a pas pu être supprimé. Réessayez.'),
        findsOneWidget,
      );
      // Still confirming: the user can try again.
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('a failure after leaving the page is ignored', (tester) async {
      final cubit = await pump(tester);
      when(() => cubit.deleteProperty(any())).thenAnswer((_) async {
        throw const PropertyDeleteFailure();
      });
      await tester.tap(find.bySemanticsLabel('Supprimer le brouillon').first);
      await tester.pump();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  setUpAll(() => registerFallbackValue(garage));
}
