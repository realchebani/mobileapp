import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/market/widgets/market_comparables.dart';
import 'package:mobileapp/seller_tunnel/market/widgets/market_range_bar.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

const nb = ' ';

ComparableSale _sale(int i, {String? street, int? rooms = 4, int? distance}) =>
    ComparableSale(
      propertyType: i.isEven ? PropertyType.house : PropertyType.apartment,
      street: street,
      areaM2: 96 + i,
      rooms: rooms,
      soldYear: 2025,
      distanceM: distance,
      priceEur: 400000 + i,
      priceM2Eur: 4000 + i,
    );

final _full = MarketSnapshot(
  id: 's1',
  propertyId: 'property-id',
  status: MarketSnapshotStatus.ok,
  createdAt: DateTime(2026, 10),
  computedAt: DateTime(2026, 9, 24, 10),
  dataUntil: DateTime(2025, 12, 19),
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
  comparablesCount: 27,
  scope: MarketScope.radius,
  radiusM: 500,
  months: 36,
  sales12m: 62,
  yoyChangePct: 2.1,
  comparables: [
    _sale(0, street: 'Rue des Platanes', distance: 400),
    _sale(1, rooms: null, distance: 1200),
    _sale(2, rooms: 0),
    _sale(3, distance: 1000),
  ],
  factors: const [
    MarketFactor(positive: true, label: 'Piscine'),
    MarketFactor(positive: false, label: 'Circulation le matin'),
  ],
  explanation: 'D’après 27 ventes comparables…',
);

void main() {
  late MockPropertyRepository repository;

  setUp(() => repository = MockPropertyRepository());

  Future<void> pump(
    WidgetTester tester, {
    MarketSnapshot? snapshot,
    PropertyFailure? error,
    MockGoRouter? goRouter,
  }) async {
    usePhoneSurface();
    when(() => repository.getMarketSnapshot('property-id'))
        .thenAnswer((_) async => error != null ? throw error : snapshot);
    await tester.pumpTunnelPage(
      const MarketSynthesisPage(),
      sellerTunnelCubit: mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            status: PropertyStatus.submitted,
          ),
        ),
      ),
      propertyRepository: repository,
      goRouter: goRouter,
    );
  }

  testWidgets('shows the market summary of the estimate', (tester) async {
    await pump(tester, snapshot: _full);
    expect(find.byType(CircularProgressIndicator), findsOne);
    await tester.pump();
    expect(find.text('Synthèse du marché'), findsOne);
    expect(find.text('Non certifiée'), findsOne);
    expect(find.text('Calculée le 24/09/2026'), findsOne);
    expect(find.text('Votre bien face au marché'), findsOne);
    expect(
      find.text(
        'Maison 115${nb}m² · Chaponost · tendance IA 479${nb}000$nb€, '
        'soit environ 4${nb}165$nb€/m².',
      ),
      findsOne,
    );
    expect(find.text('PRIX AU M² DANS VOTRE SECTEUR'), findsOne);
    expect(find.text('3${nb}572$nb€/m²'), findsOne);
    expect(find.text('Médiane secteur 4${nb}162$nb€/m²'), findsOne);
    expect(
      find.text(
        '27 ventes comparables à moins de 500${nb}m · 3${nb}dernières années',
      ),
      findsOne,
    );
    expect(
      find.text(
        'Recherche élargie faute de ventes proches et récentes$nb: ventes '
        'jusqu’à 500${nb}m, 3${nb}dernières années.',
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(RegExp('Prix au m² du secteur de 3')),
      findsOne,
    );
    expect(find.text('62'), findsOne);
    expect(find.text('+2,1$nb%'), findsOne);
    expect(find.text('Ventes comparables récentes'), findsOne);
    expect(find.text('Maison 96${nb}m² · 4${nb}p.'), findsOne);
    expect(
      find.text('Rue des Platanes · vendue en 2025 · à 400${nb}m'),
      findsOne,
    );
    expect(find.text('Appartement 97${nb}m²'), findsOne);
    expect(
      find.text('Secteur proche · vendue en 2025 · à 1,2${nb}km'),
      findsOne,
    );
    expect(find.text('Secteur proche · vendue en 2025'), findsOne);
    expect(find.text('400${nb}000$nb€'), findsOne);
    expect(find.text('Ce qui influence votre estimation'), findsOne);
    expect(find.text('Piscine'), findsOne);
    expect(find.text('−'), findsOne);
    expect(find.text('En résumé'), findsOne);
    expect(find.text('D’après 27 ventes comparables…'), findsOne);
    expect(find.textContaining('connues jusqu’en décembre 2025'), findsOne);
    expect(find.text('Partager'), findsNothing);

    // Full list.
    await tester.ensureVisible(find.text('Voir les 4 ventes'));
    await tester.tap(find.text('Voir les 4 ventes'));
    await tester.pumpAndSettle();
    expect(find.byType(MarketComparablesSheet), findsOne);
    expect(find.text('Secteur proche · vendue en 2025 · à 1${nb}km'), findsOne);
    await tester.tap(find.bySemanticsLabel('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(MarketComparablesSheet), findsNothing);
  });

  testWidgets('a minimal result: commune scope, no tiles nor lists', (
    tester,
  ) async {
    await pump(
      tester,
      snapshot: MarketSnapshot(
        id: 's1',
        propertyId: 'property-id',
        status: MarketSnapshotStatus.ok,
        createdAt: DateTime(2026, 10),
        propertyType: PropertyType.apartment,
        livingAreaM2: 60,
        medianEur: 240000,
        priceM2Low: 3500,
        priceM2Median: 4000,
        priceM2High: 4500,
        scope: MarketScope.commune,
        months: 60,
        yoyChangePct: -0.4,
      ),
    );
    await tester.pump();
    expect(
      find.text(
        'Appartement 60${nb}m² · tendance IA 240${nb}000$nb€, '
        'soit environ 4${nb}000$nb€/m².',
      ),
      findsOne,
    );
    expect(find.text('0 ventes comparables ·  · 5${nb}ans'), findsOne);
    expect(find.text('−0,4$nb%'), findsOne);
    expect(find.text('Ventes sur 12 mois'), findsNothing);
    expect(find.text('Ventes comparables récentes'), findsNothing);
    expect(find.text('Ce qui influence votre estimation'), findsNothing);
    expect(find.text('En résumé'), findsNothing);
    expect(find.textContaining('Sources'), findsOne);
    expect(find.textContaining('connues jusqu’en'), findsNothing);
  });

  testWidgets('without the sector band nor area', (tester) async {
    await pump(
      tester,
      snapshot: MarketSnapshot(
        id: 's1',
        propertyId: 'property-id',
        status: MarketSnapshotStatus.ok,
        createdAt: DateTime(2026, 10),
        sales12m: 4,
        yoyChangePct: 0,
      ),
    );
    await tester.pump();
    expect(find.byType(MarketRangeBar), findsNothing);
    expect(find.text('0,0$nb%'), findsOne);
  });

  testWidgets('no estimate: the expert takes over', (tester) async {
    await pump(tester);
    await tester.pump();
    expect(find.textContaining('Pas de synthèse du marché'), findsOne);
  });

  testWidgets('reading failure, then retry', (tester) async {
    await pump(tester, error: const PropertyLoadFailure('x'));
    await tester.pump();
    expect(
      find.text('La synthèse du marché n’a pas pu être chargée.'),
      findsOne,
    );
    when(() => repository.getMarketSnapshot('property-id'))
        .thenAnswer((_) async => _full);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Votre bien face au marché'), findsOne);
  });

  testWidgets('back buttons return to V8', (tester) async {
    final goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    await pump(tester, snapshot: _full, goRouter: goRouter);
    await tester.pump();
    await tester.tap(find.text('Retour au suivi de mon dossier'));
    await tester.tap(find.bySemanticsLabel('Retour'));
    verify(() => goRouter.go(AppRoutes.sellerSubmitted)).called(2);
  });

  test('range bar positions', () {
    expect(MarketRangeBar.position(100, 100, 200, 150), closeTo(0.237, 0.001));
    expect(MarketRangeBar.position(500, 100, 200, 500), closeTo(0.908, 0.001));
    expect(MarketRangeBar.position(0, 100, 100, 100), 0);
  });
}
