import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/sale.dart';
import 'package:mobileapp/seller_space/sale/sale_route_scope.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_scaffold.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import 'sale_helpers.dart';

void main() {
  late MockGoRouter router;

  setUp(() => router = saleRouter());

  group(SaleRouteScope, () {
    testWidgets('sales unavailable', (tester) async {
      await tester.pumpApp(
        const SaleRouteScope(saleId: 'sale-id', child: Text('child')),
        goRouter: router,
      );
      expect(
        find.text('La mise en vente n’est pas encore disponible.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retour à mes biens'));
      verify(() => router.go('/vendeur')).called(1);
    });

    testWidgets('loading, not found, failure, withdrawn, ready', (
      tester,
    ) async {
      final cubits = MockSaleCubits();
      Future<MockSaleCubit> pump(SaleState state) async {
        final cubit = mockSaleCubit(state);
        when(() => cubits.of('sale-id')).thenReturn(cubit);
        await tester.pumpApp(
          RepositoryProvider<SaleCubits>.value(
            value: cubits,
            child: SaleRouteScope(
              key: UniqueKey(),
              saleId: 'sale-id',
              child: const Text('child'),
            ),
          ),
          goRouter: router,
        );
        return cubit;
      }

      await pump(const SaleState());
      expect(find.byType(SellerLoading), findsOneWidget);
      await pump(const SaleState(status: SaleLoadStatus.notFound));
      expect(find.text('Cette vente n’existe plus.'), findsOneWidget);
      final failed = await pump(
        const SaleState(status: SaleLoadStatus.failure),
      );
      await tester.tap(find.text('Réessayer'));
      verify(failed.refresh).called(1);
      await pump(
        saleState(
          sale: const Sale(
            id: 'sale-id',
            formula: SaleFormula.essentiel,
            stage: SaleStage.withdrawn,
          ),
        ),
      );
      expect(find.text('Cette vente a été retirée.'), findsOneWidget);
      await pump(saleState());
      expect(find.text('child'), findsOneWidget);
    });
  });

  testWidgets('sale routes build their screens', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final goRouter = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: '/vendeur/ventes/sale-id',
      routes: [
        GoRoute(
          path: '/vendeur',
          builder: (context, state) => const SizedBox(),
          routes: saleRoutes(navigatorKey),
        ),
      ],
    );
    addTearDown(goRouter.dispose);
    await tester.pumpAppRouter(goRouter);
    await tester.pumpAndSettle();
    for (final location in [
      '/vendeur/ventes/sale-id/annonce',
      '/vendeur/ventes/sale-id/annonce/photos',
      '/vendeur/ventes/sale-id/annonce/apercu',
    ]) {
      goRouter.go(location);
      await tester.pumpAndSettle();
      expect(
        find.text('La mise en vente n’est pas encore disponible.'),
        findsOneWidget,
      );
    }
  });

  group(SalesScope, () {
    testWidgets('without a sale repository: the child alone', (tester) async {
      await tester.pumpApp(const SalesScope(child: Text('child')));
      final context = tester.element(find.text('child'));
      expect(salesCubitOf(context), isNull);
      expect(saleRepositoryOf(context), isNull);
    });

    testWidgets('provides the sales and the sale cubits', (tester) async {
      final repository = MockSaleRepository();
      when(() => repository.listSales('user-id')).thenAnswer((_) async => []);
      when(() => repository.getSale('sale-id')).thenAnswer((_) async => null);
      final properties = MockPropertyRepository();
      final valuations = MockValuationRepository();
      when(() => properties.getOwners(any())).thenAnswer((_) async => []);
      when(() => properties.getDocuments(any())).thenAnswer((_) async => []);
      when(() => valuations.getLatestValuation(any()))
          .thenAnswer((_) async => null);
      await tester.pumpApp(
        BlocProvider<SellerPropertiesCubit>.value(
          value: propertiesCubit(),
          child: const SalesScope(child: Text('child')),
        ),
        saleRepository: repository,
        propertyRepository: properties,
        valuationRepository: valuations,
        profileCubit: sellerProfileCubit(),
      );
      final context = tester.element(find.text('child'));
      final sales = salesCubitOf(context)!;
      await tester.pump();
      verify(() => repository.listSales('user-id')).called(1);
      expect(sales.state.status, SalesStatus.success);
      final cubit = context.read<SaleCubits>().of('sale-id');
      await tester.pump();
      expect(cubit.state.status, SaleLoadStatus.notFound);
      // A change of a sale reloads the list.
      when(() => repository.getSale('sale-id'))
          .thenAnswer((_) async => testSale);
      when(() => repository.getMandate(any())).thenAnswer((_) async => null);
      when(() => repository.getRequests(any())).thenAnswer((_) async => []);
      when(() => repository.getIdentityVerifications(any()))
          .thenAnswer((_) async => {});
      await cubit.refresh();
      await tester.pump();
      verify(() => repository.listSales('user-id')).called(1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group(SaleScaffold, () {
    testWidgets('back: pops, or goes to the seller space', (tester) async {
      await tester.pumpApp(
        const SaleScaffold(title: 'T', children: [Text('a')]),
        goRouter: router,
      );
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(router.pop).called(1);
      when(router.canPop).thenReturn(false);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => router.go('/vendeur')).called(1);
    });
  });

  group('labels', () {
    testWidgets('stages and failures', (tester) async {
      await tester.pumpApp(const Text('x'));
      final context = tester.element(find.text('x'));
      final l10n = context.l10n;
      String stage(SaleStage stage, [SaleFormula f = SaleFormula.essentiel]) =>
          saleStageLabel(context, Sale(id: 's', formula: f, stage: stage));
      expect(stage(SaleStage.planChosen), 'Mandat à signer');
      expect(stage(SaleStage.mandateSigned), contains('annonce'));
      expect(
        stage(SaleStage.mandateSigned, SaleFormula.expert),
        contains('agent'),
      );
      expect(stage(SaleStage.published), startsWith('En ligne depuis le'));
      expect(stage(SaleStage.withdrawn), 'Vente retirée');
      final messages = {
        for (final reason in SaleFailureReason.values)
          saleFailureMessage(l10n, SaleFailure(reason)),
      };
      expect(messages, hasLength(SaleFailureReason.values.length));
      expect(
        saleFailureMessage(
          l10n,
          const SaleFailure(
            SaleFailureReason.priceOutOfBounds,
            details: '140000,640000',
          ),
        ),
        contains('140\u00a0000'),
      );
      expect(
        saleFailureMessage(
          l10n,
          const SaleFailure(
            SaleFailureReason.mandateMinimumPeriod,
            details: '2026-11-02 08:00:00+00',
          ),
        ),
        contains('02/11/2026'),
      );
    });
  });
}
