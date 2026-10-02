import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/ai_estimate_card.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/dossier_summary_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_timeline.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const nb = '\u00a0';

const _owner = PropertyOwner(
  propertyId: 'property-id',
  position: 1,
  firstName: 'Sophie',
  lastName: 'Durand',
  email: 'sophie.durand@email.fr',
);

MarketSnapshot _snapshot(
  MarketSnapshotStatus status, {
  String? reason,
  int? low = 495000,
  int? median = 518000,
  int? high = 540000,
  DateTime? computedAt,
  int? confidence = 75,
  DateTime? createdAt,
}) => MarketSnapshot(
  id: 's1',
  propertyId: 'property-id',
  status: status,
  reason: reason,
  createdAt: createdAt ?? DateTime.now(),
  computedAt: computedAt,
  lowEur: low,
  medianEur: median,
  highEur: high,
  confidence: confidence,
);

void main() {
  late MockPropertyRepository repository;

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.getMarketSnapshot(any())).thenAnswer(
      (_) async =>
          _snapshot(MarketSnapshotStatus.insufficient, reason: 'too_few_sales'),
    );
    when(() => repository.requestEstimate(any())).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    Property property = const Property(
      id: 'property-id',
      ownerId: 'user-id',
      propertyType: PropertyType.house,
      status: PropertyStatus.submitted,
    ),
    List<PropertyOwner> owners = const [_owner],
    AppBloc? appBloc,
    MockGoRouter? goRouter,
    SellerTunnelCubit? cubit,
  }) async {
    usePhoneSurface();
    await tester.pumpTunnelPage(
      const SubmittedPage(),
      sellerTunnelCubit:
          cubit ??
          mockSellerTunnelCubit(
            SellerTunnelState(
              status: SellerTunnelStatus.success,
              property: property,
              owners: owners,
            ),
          ),
      appBloc: appBloc,
      goRouter: goRouter,
      propertyRepository: repository,
    );
    await tester.pump();
  }

  List<TimelineNodeState> nodeStates(WidgetTester tester) => tester
      .widget<SubmittedTimeline>(find.byType(SubmittedTimeline))
      .entries
      .map((entry) => entry.state)
      .toList();

  testWidgets('submitted: thanks the owner and shows the timeline', (
    tester,
  ) async {
    await pump(
      tester,
      property: Property(
        id: 'property-id',
        ownerId: 'user-id',
        propertyType: PropertyType.house,
        status: PropertyStatus.submitted,
        submittedAt: DateTime(2026, 9, 24, 18, 42),
      ),
    );
    expect(find.text('Merci Sophie, votre dossier est complet'), findsOne);
    expect(find.textContaining('Vous serez alerté(e)'), findsOne);
    expect(find.text('Transmis le 24/09 à 18${nb}h${nb}42'), findsOne);
    expect(find.text('Réponse estimée sous 24${nb}h'), findsOne);
    expect(
      find.text('Consultable ici, avec une notification dans l’application'),
      findsOne,
    );
    expect(nodeStates(tester), [
      TimelineNodeState.done,
      TimelineNodeState.current,
      TimelineNodeState.todo,
    ]);
    expect(find.byType(AiEstimateCard), findsNothing);
    // Notifications are in-app only (no e-mail promise).
    expect(find.text('Vous serez prévenu(e) dans l’application.'), findsOne);
    expect(find.textContaining('e-mail à'), findsNothing);
    expect(find.textContaining('Trop peu de ventes comparables'), findsOne);
    expect(find.bySemanticsLabel(RegExp('Dossier complet, Terminé')), findsOne);
    expect(
      find.bySemanticsLabel(RegExp('Analyse professionnelle, En cours')),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(RegExp('Avis de valeur certifié, À venir')),
      findsOne,
    );
  });

  testWidgets('in review: the expert is analysing', (tester) async {
    await pump(
      tester,
      property: const Property(
        id: 'property-id',
        ownerId: 'user-id',
        propertyType: PropertyType.house,
        status: PropertyStatus.inReview,
      ),
    );
    expect(find.textContaining('Un expert immobilier analyse'), findsOne);
    expect(find.text('Transmis à notre expert'), findsOne);
    expect(find.text('Un expert analyse votre dossier'), findsOne);
    expect(nodeStates(tester), [
      TimelineNodeState.done,
      TimelineNodeState.current,
      TimelineNodeState.todo,
    ]);
    expect(find.text('Vous serez prévenu(e) dans l’application.'), findsOne);
  });

  testWidgets('certified: every step done, no notice nor AI trend', (
    tester,
  ) async {
    await pump(
      tester,
      property: const Property(
        id: 'property-id',
        ownerId: 'user-id',
        propertyType: PropertyType.house,
        status: PropertyStatus.certified,
      ),
    );
    expect(find.text('Votre avis de valeur est prêt'), findsOne);
    expect(find.byType(AiEstimateCard), findsNothing);
    expect(find.text('TENDANCE IA'), findsNothing);
    verifyNever(() => repository.getMarketSnapshot(any()));
    expect(
      find.textContaining('votre avis de valeur certifié est disponible'),
      findsOne,
    );
    expect(find.text('Analyse terminée'), findsOne);
    expect(find.text('Disponible'), findsOne);
    expect(nodeStates(tester), [
      TimelineNodeState.done,
      TimelineNodeState.done,
      TimelineNodeState.done,
    ]);
    expect(
      find.text('Vous serez prévenu(e) dans l’application.'),
      findsNothing,
    );
  });

  testWidgets('draft: the dossier is not sent yet', (tester) async {
    await pump(tester, property: testProperty);
    expect(find.text('Votre dossier n’est pas encore envoyé'), findsOne);
    expect(find.textContaining('Terminez l’audit'), findsOne);
    expect(find.text('En cours de constitution'), findsOne);
    expect(nodeStates(tester), [
      TimelineNodeState.current,
      TimelineNodeState.todo,
      TimelineNodeState.todo,
    ]);
    expect(
      find.text('Vous serez prévenu(e) dans l’application.'),
      findsNothing,
    );
  });

  testWidgets('formats a UTC submission date in local time', (tester) async {
    final submittedAt = DateTime.utc(2026, 9, 24, 16, 42);
    final local = submittedAt.toLocal();
    await pump(
      tester,
      property: Property(
        id: 'property-id',
        ownerId: 'user-id',
        propertyType: PropertyType.house,
        status: PropertyStatus.submitted,
        submittedAt: submittedAt,
      ),
    );
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    expect(
      find.text('Transmis le $day/$month à ${local.hour}${nb}h$nb$minutes'),
      findsOne,
    );
  });

  testWidgets('without owner: generic thanks', (tester) async {
    await pump(tester, owners: const []);
    expect(find.text('Merci, votre dossier est complet'), findsOne);
  });

  testWidgets('without a first name: generic thanks', (tester) async {
    await pump(
      tester,
      owners: const [
        PropertyOwner(
          propertyId: 'property-id',
          position: 1,
          firstName: ' ',
          lastName: 'Durand',
        ),
      ],
    );
    expect(find.text('Merci, votre dossier est complet'), findsOne);
  });

  group('Tendance IA', () {
    testWidgets('shows the estimate and opens the market summary', (
      tester,
    ) async {
      when(() => repository.getMarketSnapshot(any())).thenAnswer(
        (_) async => _snapshot(
          MarketSnapshotStatus.ok,
          computedAt: DateTime(2026, 9, 24, 10),
        ),
      );
      final goRouter = MockGoRouter();
      when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
      await pump(tester, goRouter: goRouter);
      expect(find.byType(AiEstimateCard), findsOne);
      expect(find.text('TENDANCE IA'), findsOne);
      expect(find.text('Non certifiée'), findsOne);
      expect(find.text('495${nb}000$nb– 540${nb}000$nb€'), findsOne);
      expect(find.text('495${nb}k€'), findsOne);
      expect(find.text('Médiane 518${nb}k€'), findsOne);
      expect(find.text('540${nb}k€'), findsOne);
      expect(find.text('Fiabilité$nb: élevée'), findsOne);
      expect(find.textContaining('Calculée le 24/09/2026'), findsOne);
      expect(
        find.bySemanticsLabel(
          'Fourchette de 495${nb}000 à 540${nb}000$nb€, '
          'médiane 518${nb}000$nb€',
        ),
        findsOne,
      );
      await tester.ensureVisible(find.text('Voir la synthèse du marché'));
      await tester.tap(find.text('Voir la synthèse du marché'));
      // Pushed: back returns to V8.
      verify(
        () => goRouter.push<Object?>(AppRoutes.sellerMarket('property-id')),
      ).called(1);
      verifyNever(() => repository.requestEstimate(any()));
    });

    testWidgets('says when the search had to be widened', (tester) async {
      when(() => repository.getMarketSnapshot(any())).thenAnswer(
        (_) async => MarketSnapshot(
          id: 's1',
          propertyId: 'property-id',
          status: MarketSnapshotStatus.ok,
          createdAt: DateTime.now(),
          lowEur: 103000,
          medianEur: 123000,
          highEur: 148000,
          radiusM: 10000,
          months: 24,
        ),
      );
      await pump(tester);
      expect(
        find.text(
          'Recherche élargie faute de ventes proches et récentes$nb: ventes '
          'jusqu’à 10${nb}km, 2${nb}dernières années.',
        ),
        findsOne,
      );
    });

    testWidgets('without date, with an empty range and other reliabilities', (
      tester,
    ) async {
      when(() => repository.getMarketSnapshot(any())).thenAnswer(
        (_) async => _snapshot(
          MarketSnapshotStatus.ok,
          low: 500000,
          median: 500000,
          high: 500000,
          confidence: 50,
        ),
      );
      await pump(tester);
      expect(find.textContaining('Calculée à partir'), findsOne);
      expect(find.text('Fiabilité$nb: moyenne'), findsOne);
    });

    testWidgets('low reliability, or none', (tester) async {
      when(() => repository.getMarketSnapshot(any())).thenAnswer(
        (_) async => _snapshot(MarketSnapshotStatus.ok, confidence: 20),
      );
      await pump(tester);
      expect(find.text('Fiabilité$nb: faible'), findsOne);
    });

    testWidgets('fewer than 5 comparable sales: the expert takes over', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(AiEstimateCard), findsNothing);
      expect(find.textContaining('Trop peu de ventes comparables'), findsOne);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('no estimate for this property', (tester) async {
      when(() => repository.getMarketSnapshot(any())).thenAnswer(
        (_) async => _snapshot(
          MarketSnapshotStatus.insufficient,
          reason: 'unsupported_type',
        ),
      );
      await pump(tester);
      expect(find.textContaining('Pas de tendance automatique'), findsOne);
    });

    testWidgets('an ok result without range is shown as unavailable', (
      tester,
    ) async {
      when(
        () => repository.getMarketSnapshot(any()),
      ).thenAnswer((_) async => _snapshot(MarketSnapshotStatus.ok, low: null));
      await pump(tester);
      expect(find.byType(AiEstimateCard), findsNothing);
      expect(find.textContaining('Pas de tendance automatique'), findsOne);
    });

    testWidgets('requests the estimate when none exists, then shows it', (
      tester,
    ) async {
      final answers = [
        null,
        _snapshot(MarketSnapshotStatus.ok, computedAt: DateTime(2026, 10)),
      ];
      when(() => repository.getMarketSnapshot(any()))
          .thenAnswer((_) async => answers.removeAt(0));
      await pump(tester);
      expect(find.text('Calcul de votre tendance de prix…'), findsOne);
      verify(() => repository.requestEstimate('property-id')).called(1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byType(AiEstimateCard), findsOne);
    });

    testWidgets('too many requests today: no retry', (tester) async {
      when(() => repository.getMarketSnapshot(any()))
          .thenAnswer((_) async => null);
      when(() => repository.requestEstimate(any()))
          .thenThrow(const EstimateRateLimitFailure('x'));
      await pump(tester);
      expect(find.textContaining('Trop de demandes de calcul'), findsOne);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('the market summary link wraps with large text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      when(() => repository.getMarketSnapshot(any()))
          .thenAnswer((_) async => _snapshot(MarketSnapshotStatus.ok));
      await pump(tester);
      expect(find.text('Voir la synthèse du marché'), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('after a failure, "Réessayer" requests it again', (
      tester,
    ) async {
      final answers = [
        _snapshot(MarketSnapshotStatus.error),
        _snapshot(MarketSnapshotStatus.ok),
      ];
      when(() => repository.getMarketSnapshot(any()))
          .thenAnswer((_) async => answers.removeAt(0));
      await pump(tester);
      expect(
        find.text('Votre tendance de prix n’a pas pu être calculée.'),
        findsOne,
      );
      verifyNever(() => repository.requestEstimate(any()));
      await tester.ensureVisible(find.text('Réessayer'));
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      verify(() => repository.requestEstimate('property-id')).called(1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byType(AiEstimateCard), findsOne);
    });
  });

  testWidgets('"Aller au tableau de bord" opens the dashboard', (tester) async {
    final goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    await pump(tester, goRouter: goRouter);
    await tester.ensureVisible(find.text('Aller au tableau de bord'));
    await tester.tap(find.text('Aller au tableau de bord'));
    verify(() => goRouter.go(AppRoutes.seller)).called(1);
  });

  testWidgets('opens and closes the data summary', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Voir l’aperçu de mes données'));
    await tester.tap(find.text('Voir l’aperçu de mes données'));
    await tester.pumpAndSettle();
    expect(find.byType(DossierSummarySheet), findsOne);
    expect(find.text('Sophie Durand'), findsOne);
    await tester.tap(find.bySemanticsLabel('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(DossierSummarySheet), findsNothing);
  });

  testWidgets('the summary button label fits with large text on 375', (
    tester,
  ) async {
    await loadRealestyFonts();
    await pump(tester);
    tester.view.physicalSize = const Size(375, 812);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    final finder = find.text('Voir l’aperçu de mes données');
    await tester.ensureVisible(finder);
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a type the estimate does not cover: the expert, no request', (
    tester,
  ) async {
    final repository = MockPropertyRepository();
    await tester.pumpTunnelPage(
      const SubmittedPage(),
      sellerTunnelCubit: mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.commercial,
            status: PropertyStatus.submitted,
          ),
        ),
      ),
      propertyRepository: repository,
    );
    await tester.pump();
    verifyNever(() => repository.getMarketSnapshot(any()));
    verifyNever(() => repository.requestEstimate(any()));
  });
}
