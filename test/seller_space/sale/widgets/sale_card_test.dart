import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/sale/offer_choice/offer_choice_sheet.dart';
import 'package:mobileapp/seller_space/sale/sale.dart';
import 'package:mobileapp/seller_space/sale/widgets/withdraw_sheet.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../helpers/helpers.dart';
import '../../fixtures.dart';
import '../sale_helpers.dart';

const _lot = PropertyLot(
  id: 'lot',
  ownerId: 'user-id',
  saleMode: LotSaleMode.togetherOrSeparately,
  mainPropertyId: 'property-id',
);

const _member = Property(
  id: 'property-id',
  ownerId: 'user-id',
  status: PropertyStatus.certified,
  lotId: 'lot',
);

const _other = Property(
  id: 'other',
  ownerId: 'user-id',
  status: PropertyStatus.submitted,
  lotId: 'lot',
);

void main() {
  late MockSaleRepository repository;
  late MockValuationRepository valuations;
  late MockGoRouter router;
  late MockSaleCubits cubits;
  late MockSaleCubit saleCubit;

  setUpAll(() async {
    await loadRealestyFonts();
    registerFallbackValue(SaleFormula.essentiel);
  });

  setUp(() {
    repository = MockSaleRepository();
    valuations = MockValuationRepository();
    router = saleRouter();
    cubits = MockSaleCubits();
    saleCubit = mockSaleCubit(saleState());
    when(() => cubits.of(any())).thenReturn(saleCubit);
    when(() => valuations.getLatestValuation(any()))
        .thenAnswer((_) async => testValuation);
  });

  Future<MockSalesCubit> pump(
    WidgetTester tester,
    Widget child, {
    List<Sale>? sales = const [],
    List<Property> properties = const [certifiedProperty],
    List<PropertyLot> lots = const [],
  }) async {
    useTallSurface(1400);
    final salesCubit = salesCubit_(sales);
    await tester.pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<SellerPropertiesCubit>.value(
            value: propertiesCubit(properties: properties, lots: lots),
          ),
          if (salesCubit != null) ...[
            BlocProvider<SalesCubit>.value(value: salesCubit),
            RepositoryProvider<SaleCubits>.value(value: cubits),
          ],
        ],
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
      saleRepository: sales == null ? null : repository,
      valuationRepository: valuations,
      goRouter: router,
    );
    await tester.pumpAndSettle();
    return salesCubit ?? salesCubit_(const [])!;
  }

  group(PropertySaleCard, () {
    testWidgets('without sales: the coming soon card', (tester) async {
      await pump(
        tester,
        const PropertySaleCard(property: certifiedProperty),
        sales: null,
      );
      await tester.tap(find.text('Mettre mon bien en vente'));
      await tester.pump();
      expect(find.textContaining('arrive bientôt'), findsOneWidget);
      await pump(tester, const PropertySaleCard(property: _other), sales: null);
      expect(find.byType(ActionCard), findsNothing);
    });

    testWidgets('V10 creates the sale and opens it', (tester) async {
      when(
        () => repository.chooseFormula(
          saleId: any(named: 'saleId'),
          formula: any(named: 'formula'),
          propertyId: any(named: 'propertyId'),
          lotId: any(named: 'lotId'),
        ),
      ).thenAnswer((_) async => 'sale-id');
      final sales = await pump(
        tester,
        const PropertySaleCard(property: certifiedProperty),
      );
      await tester.tap(find.text('Mettre mon bien en vente'));
      await tester.pumpAndSettle();
      expect(find.byType(OfferChoiceSheet), findsOneWidget);
      expect(find.textContaining('5 250'), findsOneWidget);
      await tester.screenshot('v10_offer_choice');
      await tester.tap(find.text('Choisir Le Premium'));
      await tester.pumpAndSettle();
      verify(
        () => repository.chooseFormula(
          saleId: any(named: 'saleId'),
          formula: SaleFormula.premium,
          propertyId: 'property-id',
        ),
      ).called(1);
      verify(sales.load).called(1);
      verify(() => router.push<Object?>('/vendeur/ventes/sale-id')).called(1);
    });

    testWidgets('V10: refusals are told; closing does nothing', (tester) async {
      when(
        () => repository.chooseFormula(
          saleId: any(named: 'saleId'),
          formula: any(named: 'formula'),
          propertyId: any(named: 'propertyId'),
          lotId: any(named: 'lotId'),
        ),
      ).thenThrow(const SaleFailure(SaleFailureReason.lotOnSale));
      await pump(tester, const PropertySaleCard(property: certifiedProperty));
      await tester.tap(find.text('Mettre mon bien en vente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 %'));
      await tester.pump();
      expect(find.textContaining('15 750'), findsOneWidget);
      await tester.tap(find.text('Choisir L’Expert'));
      await tester.pumpAndSettle();
      expect(find.text('Le lot de ce bien est déjà en vente.'), findsOneWidget);
      when(
        () => repository.chooseFormula(
          saleId: any(named: 'saleId'),
          formula: any(named: 'formula'),
          propertyId: any(named: 'propertyId'),
          lotId: any(named: 'lotId'),
        ),
      ).thenThrow(Exception());
      await tester.tap(find.text('1 %'));
      await tester.pump();
      await tester.tap(find.text('Choisir L’Essentiel'));
      await tester.pumpAndSettle();
      expect(find.text('Une erreur est survenue. Réessayez.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      verifyNever(() => router.push<Object?>(any()));
    });

    testWidgets('a lot member: this property or the whole lot', (tester) async {
      when(
        () => repository.chooseFormula(
          saleId: any(named: 'saleId'),
          formula: any(named: 'formula'),
          propertyId: any(named: 'propertyId'),
          lotId: any(named: 'lotId'),
        ),
      ).thenAnswer((_) async => 'sale-id');
      await pump(
        tester,
        const PropertySaleCard(property: _member),
        properties: const [_member, _other],
        lots: const [_lot],
      );
      await tester.tap(find.text('Mettre mon bien en vente'));
      await tester.pumpAndSettle();
      expect(find.text('Ce bien seul'), findsOneWidget);
      await tester.tap(find.text('Le lot (2 biens)'));
      await tester.pump();
      await tester.tap(find.text('Choisir Le Premium'));
      await tester.pumpAndSettle();
      verify(
        () => repository.chooseFormula(
          saleId: any(named: 'saleId'),
          formula: SaleFormula.premium,
          lotId: 'lot',
        ),
      ).called(1);
    });

    testWidgets('only the lot; nothing to sell', (tester) async {
      await pump(
        tester,
        const PropertySaleCard(property: _other),
        properties: const [_member, _other],
        lots: const [
          PropertyLot(
            id: 'lot',
            ownerId: 'user-id',
            mainPropertyId: 'property-id',
          ),
        ],
      );
      expect(find.text('Mettre le lot en vente'), findsOneWidget);
      await pump(
        tester,
        const PropertySaleCard(property: _other),
        properties: const [_other],
      );
      expect(find.byType(ActionCard), findsNothing);
    });

    testWidgets('on sale: "Ma vente", continue, withdraw', (tester) async {
      await pump(
        tester,
        const PropertySaleCard(property: certifiedProperty),
        sales: const [testSale],
      );
      expect(find.text('Ma vente'), findsOneWidget);
      expect(find.text('Mandat à signer'), findsOneWidget);
      await tester.screenshot('v9_sale_card');
      await tester.tap(find.text('Continuer'));
      verify(() => router.push<Object?>('/vendeur/ventes/sale-id')).called(1);
      await tester.tap(find.text('Retirer de la vente'));
      await tester.pumpAndSettle();
      expect(find.byType(WithdrawSaleSheet), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' Trop tôt ');
      await tester.tap(find.text('Retirer de la vente').last);
      await tester.pumpAndSettle();
      verify(() => saleCubit.withdraw(reason: 'Trop tôt')).called(1);
      expect(find.text('Votre vente est retirée.'), findsOneWidget);
    });

    testWidgets('withdraw: refused, cancelled, without reason', (tester) async {
      when(() => saleCubit.state).thenReturn(
        saleState(failure: const SaleFailure(SaleFailureReason.saleNotFound)),
      );
      await pump(
        tester,
        const PropertySaleCard(property: certifiedProperty),
        sales: const [testSale],
      );
      await tester.tap(find.text('Retirer de la vente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer de la vente').last);
      await tester.pumpAndSettle();
      verify(() => saleCubit.withdraw()).called(1);
      expect(find.text('Cette vente n’existe plus.'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(WithdrawSaleSheet), findsNothing);
    });

    testWidgets('a signed 1 % sale opens its listing; a lot sale', (
      tester,
    ) async {
      await pump(
        tester,
        const PropertySaleCard(property: _member),
        properties: const [_member, _other],
        lots: const [_lot],
        sales: [
          Sale(
            id: 'sale-id',
            lotId: 'lot',
            formula: SaleFormula.premium,
            stage: SaleStage.published,
            publishedAt: DateTime(2026, 10, 3),
          ),
        ],
      );
      expect(find.text('Ma vente · lot'), findsOneWidget);
      expect(find.text('2 biens vendus ensemble'), findsOneWidget);
      expect(find.textContaining('En ligne depuis le'), findsOneWidget);
      await tester.tap(find.text('Continuer'));
      verify(() => router.push<Object?>('/vendeur/ventes/sale-id/annonce'))
          .called(1);
    });
  });

  group(LotSaleCard, () {
    testWidgets('states of a lot', (tester) async {
      await pump(tester, const LotSaleCard(lot: _lot), sales: null);
      expect(find.byType(ActionCard), findsNothing);
      await pump(
        tester,
        const LotSaleCard(lot: _lot),
        properties: const [_member, _other],
      );
      expect(find.text('Mettre le lot en vente'), findsOneWidget);
      await tester.tap(find.text('Mettre le lot en vente'));
      await tester.pumpAndSettle();
      expect(find.byType(OfferChoiceSheet), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      await pump(
        tester,
        const LotSaleCard(lot: _lot),
        properties: const [_member, _other],
        sales: const [
          Sale(
            id: 's',
            propertyId: 'property-id',
            formula: SaleFormula.essentiel,
            stage: SaleStage.planChosen,
          ),
        ],
      );
      expect(find.textContaining('en vente seul'), findsOneWidget);
      await pump(
        tester,
        const LotSaleCard(lot: _lot),
        properties: const [_other],
      );
      expect(
        find.textContaining('bien principal sera certifié'),
        findsOneWidget,
      );
      await pump(
        tester,
        const LotSaleCard(lot: _lot),
        properties: const [_member, _other],
        sales: const [
          Sale(
            id: 's',
            lotId: 'lot',
            formula: SaleFormula.expert,
            stage: SaleStage.mandateSigned,
          ),
        ],
      );
      expect(
        find.text('Mandat signé · un agent vous contacte sous 24 h'),
        findsOneWidget,
      );
    });
  });

  group('startSaleFor', () {
    testWidgets('opens the sale, V10, or tells', (tester) async {
      Future<void> start(
        Property property, {
        List<Sale>? sales = const [],
      }) async {
        await pump(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => startSaleFor(context, property),
              child: const Text('go'),
            ),
          ),
          sales: sales,
          properties: [property],
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
      }

      await start(certifiedProperty, sales: null);
      expect(find.textContaining('arrive bientôt'), findsOneWidget);
      await start(certifiedProperty, sales: const [testSale]);
      verify(() => router.push<Object?>('/vendeur/ventes/sale-id')).called(1);
      await start(certifiedProperty);
      expect(find.byType(OfferChoiceSheet), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      await start(_other);
      expect(find.text('Ce bien n’est pas encore certifié.'), findsOneWidget);
    });
  });
}

MockSalesCubit? salesCubit_(List<Sale>? sales) =>
    sales == null ? null : salesCubit(sales);
