import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';
import '../pump_seller_space.dart';

void main() {
  const nb = ' ';
  late MockGoRouter goRouter;
  late MockValuationRepository repository;
  late List<Uri> opened;
  late bool openResult;

  setUpAll(() async {
    registerFallbackValue(Uri());
    await loadRealestyFonts();
  });

  setUp(() {
    usePhoneSurface();
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    when(() => goRouter.canPop()).thenReturn(false);
    when(goRouter.pop).thenReturn(null);
    repository = MockValuationRepository();
    when(() => repository.getReportUrl(any()))
        .thenAnswer((_) async => 'https://example.com/report.pdf');
    opened = [];
    openResult = true;
  });

  final minimal = Valuation(
    id: 'v',
    propertyId: 'property-id',
    valueEur: 300000,
    lowEur: 290000,
    highEur: 310000,
    expertDisplayName: 'Anne Expert',
    certifiedAt: DateTime(2026, 9, 25),
    validUntil: DateTime(2026, 12, 25),
    comparables: const [ValuationComparable(street: 'rue B', priceEur: 300000)],
    competitors: const [ValuationCompetitor(label: 'T3')],
  );

  Future<void> pump(
    WidgetTester tester, {
    Valuation? valuation,
    SellerTunnelState state = certifiedState,
    ValuationState? valuationState,
    ValuationCubit? valuationCubit,
  }) {
    return tester.pumpSellerSpacePage(
      ReportPage(
        openUrl: (uri) async {
          opened.add(uri);
          return openResult;
        },
      ),
      sellerTunnelCubit: mockSellerTunnelCubit(state),
      valuationCubit:
          valuationCubit ??
          mockValuationCubit(
            valuationState ??
                ValuationState(
                  status: ValuationStatus.success,
                  valuation: valuation ?? testValuation,
                ),
          ),
      valuationRepository: repository,
      goRouter: goRouter,
    );
  }

  Future<void> showTab(WidgetTester tester, String tab) async {
    await tester.scrollUntilVisible(find.text(tab), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200);
    await tester.pumpAndSettle();
  }

  test('opens the PDF with url_launcher by default', () {
    expect(const ReportPage().openUrl, isNotNull);
  });

  testWidgets('hero and PDF download', (tester) async {
    await pump(tester);
    expect(find.text('Rapport d’avis de valeur'), findsOneWidget);
    expect(find.text('12 rue de la Colombe'), findsOneWidget);
    expect(find.text('69630 Chaponost · Maison 115${nb}m²'), findsOneWidget);
    expect(find.text('Certifié'), findsOneWidget);
    expect(
      find.text(
        'Fourchette 505${nb}000$nb€ – 545${nb}000$nb€ · soit 4${nb}565$nb€/m²',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Validé par Julien M., expert immobilier · 25 septembre 2026'),
      findsOneWidget,
    );

    await tester.tap(find.text('Télécharger le rapport (PDF · 11 pages)'));
    await tester.pumpAndSettle();
    verify(() => repository.getReportUrl('user-id/property-id/report.pdf'))
        .called(1);
    expect(opened, [Uri.parse('https://example.com/report.pdf')]);
    expect(find.textContaining('Impossible d’ouvrir'), findsNothing);
  });

  testWidgets('reports a PDF that cannot be opened', (tester) async {
    openResult = false;
    await pump(tester);
    await tester.tap(find.text('Télécharger le rapport (PDF · 11 pages)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossible d’ouvrir'), findsOneWidget);
  });

  testWidgets('reports a PDF URL that cannot be signed', (tester) async {
    when(() => repository.getReportUrl(any()))
        .thenThrow(const ValuationLoadFailure());
    await pump(tester);
    await tester.tap(find.text('Télécharger le rapport (PDF · 11 pages)'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.textContaining('Impossible d’ouvrir'), findsOneWidget);
  });

  testWidgets('back goes to the dashboard, or pops', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Retour'));
    verify(() => goRouter.go(AppRoutes.seller)).called(1);
    when(() => goRouter.canPop()).thenReturn(true);
    await tester.tap(find.bySemanticsLabel('Retour'));
    verify(goRouter.pop).called(1);
  });

  testWidgets('Synthèse', (tester) async {
    await pump(tester);
    expect(find.text('PRIX CONSEILLÉ'), findsOneWidget);
    expect(find.text('≈ 8 sem.'), findsOneWidget);
    await scrollTo(tester, find.text('Constat de visite'));
    expect(find.text('+ 4${nb}000$nb€'), findsOneWidget);
    await scrollTo(tester, find.text('Salle de bain à rafraîchir'));
    expect(find.bySemanticsLabel(RegExp('Point faible')), findsOneWidget);
    await scrollTo(tester, find.text('très peu de visites'));
    await scrollTo(tester, find.textContaining('Ce bien réunit'));
    expect(find.text('Julien M. · Expert immobilier · Realesty'), findsOne);
    final sell = find.text('Mettre en vente à 525${nb}000$nb€');
    await scrollTo(tester, sell);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(sell);
    await tester.pump();
    expect(find.textContaining('arrive bientôt'), findsOneWidget);
  });

  testWidgets('Le bien', (tester) async {
    await pump(tester);
    await showTab(tester, 'Le bien');
    expect(find.text('Maison familiale de 115 m² avec piscine.'), findsOne);
    expect(find.text('1998 · parpaing'), findsOneWidget);
    // Legend + one tag per line.
    expect(find.text('Déclaré'), findsNWidgets(2));
    expect(find.text('Vérifié'), findsNWidgets(2));
    await scrollTo(tester, find.text('Surface habitable totale'));
    expect(
      find.text('Relevé par scan pièce par pièce dans l’appli.'),
      findsOne,
    );
    for (final group in ['REZ-DE-CHAUSSÉE', 'ÉTAGE', 'NIVEAU NON PRÉCISÉ']) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
    expect(find.text('ANNEXES'), findsOneWidget);
    expect(find.text('38,5${nb}m²'), findsOneWidget);
    expect(find.text('115${nb}m²'), findsWidgets);
  });

  testWidgets('Secteur', (tester) async {
    await pump(tester);
    await showTab(tester, 'Secteur');
    expect(find.text('rue Lucien Cozon'), findsOneWidget);
    expect(
      find.text('10/2025 · 107${nb}m² · terrain 576${nb}m²'),
      findsOneWidget,
    );
    expect(find.text('4${nb}271$nb€/m²'), findsOneWidget);
    expect(find.text('Écartée'), findsOneWidget);
    await scrollTo(tester, find.text('Retenu'));
    expect(find.text('T5 · 113 m² · 429${nb}000$nb€'), findsOneWidget);
    expect(find.text('Comparable direct · 114${nb}j en ligne'), findsOne);
    expect(find.text('Écarté'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    await scrollTo(tester, find.textContaining('Sols et risques'));
  });

  testWidgets('Prix', (tester) async {
    await pump(tester);
    await showTab(tester, 'Prix');
    expect(find.text('489${nb}000$nb€'), findsOneWidget);
    expect(find.text('+ 20${nb}000$nb€'), findsOneWidget);
    expect(find.text('− 5${nb}000$nb€'), findsOneWidget);
    await scrollTo(tester, find.text('Vous gardez en plus'));
    expect(find.text('519${nb}750$nb€'), findsOneWidget);
    expect(find.text('504${nb}000$nb€'), findsOneWidget);
    expect(find.text('+ 15${nb}750$nb€'), findsOneWidget);
    await scrollTo(tester, find.text('Coût total de son projet'));
    expect(find.text('39${nb}400$nb€'), findsOneWidget);
    expect(find.text('+ Salle de bain à rafraîchir'), findsOneWidget);
    expect(find.text('569${nb}400$nb€'), findsOneWidget);
    await scrollTo(tester, find.textContaining('validité 3 mois'));
    expect(find.textContaining('jusqu’au 25 décembre 2026'), findsOneWidget);
    expect(find.text('Sources · Base DVF · Géorisques'), findsOneWidget);
  });

  testWidgets('a minimal report hides the empty sections', (tester) async {
    await pump(
      tester,
      valuation: minimal,
      state: const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'property-id',
          ownerId: 'user-id',
          status: PropertyStatus.certified,
          addressLabel: 'Lieu-dit Les Prés',
        ),
      ),
    );
    expect(find.text('Lieu-dit Les Prés'), findsOneWidget);
    expect(find.textContaining('Télécharger'), findsNothing);
    expect(find.text('Comment nous arrivons à ce chiffre'), findsNothing);
    expect(find.text('DÉLAI ESTIMÉ'), findsNothing);
    expect(find.text('AE'), findsOneWidget);

    await showTab(tester, 'Le bien');
    expect(find.text('Fiche technique'), findsNothing);
    expect(find.text('Surfaces pièce par pièce'), findsNothing);

    await showTab(tester, 'Secteur');
    expect(find.text('rue B'), findsOneWidget);
    expect(find.text('Retenu'), findsOneWidget);

    await showTab(tester, 'Prix');
    expect(find.text('Ce qui déplace le prix'), findsNothing);
    expect(find.textContaining('Travaux'), findsNothing);
    expect(find.textContaining('Sources'), findsNothing);
  });

  testWidgets('works with defaults and declared surfaces', (tester) async {
    await pump(
      tester,
      valuation: Valuation(
        id: 'v',
        propertyId: 'property-id',
        valueEur: 300000,
        lowEur: 290000,
        highEur: 310000,
        expertDisplayName: 'Anne',
        certifiedAt: DateTime(2026, 9, 25),
        validUntil: DateTime(2026, 12, 25),
        reportStoragePath: 'a.pdf',
        worksEstimateEur: 1000,
      ),
      state: const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'property-id',
          ownerId: 'user-id',
          status: PropertyStatus.certified,
        ),
        rooms: [Room(propertyId: 'property-id', name: 'Séjour', areaM2: 20)],
      ),
    );
    expect(find.text('Mon bien'), findsOneWidget);
    expect(find.text('Télécharger le rapport (PDF)'), findsOneWidget);

    await showTab(tester, 'Le bien');
    expect(find.text('Déclaré pièce par pièce dans l’appli.'), findsOne);
    expect(find.text('20${nb}m²'), findsNWidgets(2));

    await showTab(tester, 'Secteur');
    expect(
      find.text('L’expert n’a pas ajouté de données de marché à ce rapport.'),
      findsOneWidget,
    );

    await showTab(tester, 'Prix');
    await scrollTo(tester, find.text('+ Travaux à prévoir'));
  });

  testWidgets('loading, failure and missing states', (tester) async {
    await pump(tester, valuationState: const ValuationState());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final failed = mockValuationCubit(
      const ValuationState(status: ValuationStatus.failure),
    );
    await pump(tester, valuationCubit: failed);
    await tester.tap(find.text('Réessayer'));
    verify(() => failed.load('property-id')).called(1);

    await pump(
      tester,
      valuationState: const ValuationState(status: ValuationStatus.success),
    );
    expect(
      find.text('Votre avis de valeur n’est pas encore disponible.'),
      findsOneWidget,
    );

    // A dossier that is not certified has no report.
    await pump(tester, state: mockSellerTunnelCubit().state);
    expect(
      find.text('Votre avis de valeur n’est pas encore disponible.'),
      findsOneWidget,
    );
  });
}
