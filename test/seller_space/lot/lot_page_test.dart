import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/lot/create_lot_sheet.dart';
import 'package:mobileapp/seller_space/lot/lot_member_sheet.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';
import '../pump_seller_space.dart';

void main() {
  const ownerId = 'user-id';
  const house = Property(
    id: 'house',
    ownerId: ownerId,
    propertyType: PropertyType.house,
    status: PropertyStatus.submitted,
    lotId: 'lot',
    aiEstimateLowEur: 300000,
    aiEstimateMedianEur: 320000,
    aiEstimateHighEur: 340000,
  );
  const garage = Property(
    id: 'garage',
    ownerId: ownerId,
    propertyType: PropertyType.parking,
    lotId: 'lot',
  );
  const land = Property(
    id: 'land',
    ownerId: ownerId,
    propertyType: PropertyType.land,
  );
  const lot = PropertyLot(id: 'lot', ownerId: ownerId, mainPropertyId: 'house');

  late MockGoRouter goRouter;
  late MockSellerPropertiesCubit cubit;

  setUpAll(() {
    registerFallbackValue(house);
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(LotSaleMode.together);
  });

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Property> properties = const [house, garage, land],
    List<PropertyLot> lots = const [lot],
    Map<String, Set<String>> parcels = const {},
  }) async {
    cubit = mockSellerPropertiesCubit(
      properties: properties,
      lots: lots,
      parcels: parcels,
    );
    when(() => cubit.updateLot(any(), any())).thenAnswer((_) async {});
    when(() => cubit.setLot(any(), any())).thenAnswer((_) async {});
    when(() => cubit.deleteLot(any())).thenAnswer((_) async {});
    const lotId = 'lot';
    await tester.pumpSellerSpacePage(
      // ignore: prefer_const_constructors (covers the constructor)
      LotPage(lotId: lotId),
      sellerPropertiesCubit: cubit,
      goRouter: goRouter,
    );
  }

  group(LotPage, () {
    testWidgets('shows the properties, the sale mode and the estimate', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 4000);
      addTearDown(tester.view.reset);
      await pump(tester);
      expect(find.text('Lot de vente'), findsOneWidget);
      expect(find.text('Principal'), findsOneWidget);
      expect(find.text('Vendus ensemble'), findsWidgets);
      // The garage is not estimated yet: no sum.
      expect(
        find.text(
          'La tendance du lot s’affichera quand chaque bien estimable aura '
          'la sienne.',
        ),
        findsOneWidget,
      );
      expect(find.text('En attente de l’envoi du dossier'), findsOneWidget);

      await tester.tap(find.text('Maison').first);
      verify(() => goRouter.go('/vendeur/biens/house')).called(1);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go('/vendeur')).called(1);
    });

    testWidgets('changes the lot', (tester) async {
      tester.view.physicalSize = const Size(1170, 4000);
      addTearDown(tester.view.reset);
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'Maison + garage');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      verify(
        () => cubit.updateLot('lot', {
          PropertyLotColumns.name: 'Maison + garage',
        }),
      ).called(1);

      await tester.tap(find.text('Définir comme bien principal'));
      await tester.pump();
      verify(
        () => cubit.updateLot('lot', {
          PropertyLotColumns.mainPropertyId: 'garage',
        }),
      ).called(1);

      await tester.tap(find.text('Ensemble ou séparément'));
      await tester.pump();
      verify(
        () => cubit.updateLot('lot', {
          PropertyLotColumns.saleMode: LotSaleMode.togetherOrSeparately,
        }),
      ).called(1);

      await tester.tap(find.text('Retirer du lot').last);
      await tester.pump();
      verify(() => cubit.setLot(garage, null)).called(1);

      await tester.tap(find.text('Ajouter un bien au lot'));
      await tester.pumpAndSettle();
      expect(find.byType(LotMemberSheet), findsOneWidget);
      await tester.tap(find.text('Terrain'));
      await tester.pumpAndSettle();
      verify(() => cubit.setLot(land, 'lot')).called(1);

      await tester.tap(find.text('Ajouter un bien au lot'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      verifyNever(() => cubit.setLot(land, 'lot'));
    });

    testWidgets('keeps an unchanged name', (tester) async {
      await pump(
        tester,
        lots: const [PropertyLot(id: 'lot', ownerId: ownerId, name: 'Lot')],
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      verifyNever(() => cubit.updateLot(any(), any()));
      await tester.enterText(find.byType(TextField), '  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      verify(() => cubit.updateLot('lot', {PropertyLotColumns.name: null}))
          .called(1);
    });

    testWidgets('dissolves the lot after confirmation', (tester) async {
      tester.view.physicalSize = const Size(1170, 4000);
      addTearDown(tester.view.reset);
      await pump(tester);
      await tester.tap(find.text('Dissoudre le lot'));
      await tester.pump();
      expect(
        find.text(
          'Les biens restent dans Mes biens, vendus chacun séparément.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pump();
      await tester.tap(find.text('Dissoudre le lot'));
      await tester.pump();
      await tester.tap(find.text('Dissoudre le lot').last);
      await tester.pump();
      verify(() => cubit.deleteLot('lot')).called(1);
      verify(() => goRouter.go('/vendeur')).called(1);
    });

    testWidgets('tells when a change failed', (tester) async {
      tester.view.physicalSize = const Size(1170, 4000);
      addTearDown(tester.view.reset);
      await pump(tester);
      when(() => cubit.updateLot(any(), any()))
          .thenAnswer((_) async => throw const LotFrozenFailure());
      await tester.tap(find.text('Ensemble ou séparément'));
      await tester.pump();
      expect(
        find.textContaining('le lot ne peut plus être modifié'),
        findsOneWidget,
      );

      when(() => cubit.setLot(any(), any()))
          .thenAnswer((_) async => throw const PropertySaveFailure());
      await tester.tap(find.text('Retirer du lot').last);
      await tester.pumpAndSettle();
      expect(
        find.text('La modification n’a pas pu être enregistrée. Réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('a frozen lot is read only, with the sum of its estimates', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 4000);
      addTearDown(tester.view.reset);
      await pump(
        tester,
        properties: const [
          Property(
            id: 'house',
            ownerId: ownerId,
            propertyType: PropertyType.house,
            status: PropertyStatus.inReview,
            lotId: 'lot',
            aiEstimateLowEur: 300000,
            aiEstimateMedianEur: 320000,
            aiEstimateHighEur: 340000,
          ),
          Property(
            id: 'garage',
            ownerId: ownerId,
            propertyType: PropertyType.parking,
            lotId: 'lot',
          ),
          Property(
            id: 'cellar',
            ownerId: ownerId,
            propertyType: PropertyType.commercial,
            lotId: 'lot',
          ),
        ],
        parcels: const {
          'house': {'P1'},
          'garage': {'P1'},
        },
      );
      expect(
        find.textContaining('le lot ne peut plus être modifié'),
        findsOneWidget,
      );
      expect(find.text('Dissoudre le lot'), findsNothing);
      expect(find.text('Retirer du lot'), findsNothing);
      expect(find.text('Ajouter un bien au lot'), findsNothing);
      expect(
        find.text('Compris dans l’estimation du bien principal'),
        findsOneWidget,
      );
      expect(find.text('Estimé par l’expert'), findsOneWidget);
      expect(
        find.text(
          'Somme des tendances des biens, indicative et non certifiée.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a lot that no longer exists', (tester) async {
      await pump(tester, lots: const []);
      expect(find.text('Ce lot n’existe plus.'), findsOneWidget);
    });
  });

  group(CreateLotSheet, () {
    testWidgets('groups at least two properties', (tester) async {
      cubit = mockSellerPropertiesCubit(
        properties: const [
          Property(id: 'a', ownerId: ownerId, propertyType: PropertyType.house),
          Property(
            id: 'b',
            ownerId: ownerId,
            propertyType: PropertyType.parking,
          ),
        ],
      );
      when(
        () => cubit.createLot(
          lotId: any(named: 'lotId'),
          members: any(named: 'members'),
          saleMode: any(named: 'saleMode'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpSellerSpacePage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCreateLotSheet(context),
            child: const Text('open'),
          ),
        ),
        sellerPropertiesCubit: cubit,
        goRouter: goRouter,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Créer le lot'));
      await tester.pump();
      verifyNever(
        () => cubit.createLot(
          lotId: any(named: 'lotId'),
          members: any(named: 'members'),
        ),
      );
      await tester.tap(find.text('Maison'));
      await tester.tap(find.text('Garage / parking'));
      await tester.pump();
      await tester.tap(find.text('Garage / parking'));
      await tester.pump();
      expect(
        tester
            .widgetList<RealestyCheckbox>(find.byType(RealestyCheckbox))
            .where((box) => box.value),
        hasLength(1),
      );
      await tester.tap(find.text('Garage / parking'));
      await tester.tap(find.text('Ensemble ou séparément'));
      await tester.pump();
      await tester.tap(find.text('Créer le lot'));
      await tester.pumpAndSettle();
      verify(
        () => cubit.createLot(
          lotId: any(named: 'lotId'),
          members: any(named: 'members', that: hasLength(2)),
          saleMode: LotSaleMode.togetherOrSeparately,
        ),
      ).called(1);
      verify(() => goRouter.go(any(that: startsWith('/vendeur/lots/'))))
          .called(1);
    });

    testWidgets('tells when the lot could not be created', (tester) async {
      cubit = mockSellerPropertiesCubit(
        properties: const [
          Property(id: 'a', ownerId: ownerId, propertyType: PropertyType.house),
          Property(id: 'b', ownerId: ownerId, propertyType: PropertyType.land),
        ],
      );
      when(
        () => cubit.createLot(
          lotId: any(named: 'lotId'),
          members: any(named: 'members'),
          saleMode: any(named: 'saleMode'),
        ),
      ).thenAnswer((_) async => throw const PropertySaveFailure());
      await tester.pumpSellerSpacePage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCreateLotSheet(context),
            child: const Text('open'),
          ),
        ),
        sellerPropertiesCubit: cubit,
        goRouter: goRouter,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maison'));
      await tester.tap(find.text('Terrain'));
      await tester.tap(find.text('Créer le lot'));
      await tester.pumpAndSettle();
      expect(
        find.text('La modification n’a pas pu être enregistrée. Réessayez.'),
        findsOneWidget,
      );
      verifyNever(() => goRouter.go(any()));
      // Dismissed without a lot.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      verifyNever(() => goRouter.go(any()));
    });
  });

  testWidgets('LotMemberSheet without candidate', (tester) async {
    await tester.pumpSellerSpacePage(const LotMemberSheet(candidates: []));
    expect(
      find.text('Aucun autre bien ne peut rejoindre ce lot.'),
      findsOneWidget,
    );
  });

  testWidgets('a failure after leaving the lot page is ignored', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 4000);
    addTearDown(tester.view.reset);
    await pump(tester);
    when(() => cubit.updateLot(any(), any())).thenAnswer((_) async {
      throw const PropertySaveFailure();
    });
    await tester.tap(find.text('Ensemble ou séparément'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
