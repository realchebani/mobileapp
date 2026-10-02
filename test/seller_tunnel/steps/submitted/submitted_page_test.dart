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

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Property property = const Property(
      id: 'property-id',
      ownerId: 'user-id',
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
        status: PropertyStatus.certified,
        aiEstimateLowEur: 495000,
        aiEstimateMedianEur: 518000,
        aiEstimateHighEur: 540000,
      ),
    );
    expect(find.text('Votre avis de valeur est prêt'), findsOne);
    expect(find.byType(AiEstimateCard), findsNothing);
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

  testWidgets('shows the AI trend when it was computed', (tester) async {
    await pump(
      tester,
      property: Property(
        id: 'property-id',
        ownerId: 'user-id',
        status: PropertyStatus.submitted,
        aiEstimateLowEur: 495000,
        aiEstimateMedianEur: 518000,
        aiEstimateHighEur: 540000,
        aiEstimateComputedAt: DateTime(2026, 9, 24, 10),
      ),
    );
    expect(find.byType(AiEstimateCard), findsOne);
    expect(find.text('TENDANCE IA'), findsOne);
    expect(find.text('Indicative'), findsOne);
    expect(find.text('495${nb}000$nb– 540${nb}000$nb€'), findsOne);
    expect(find.text('495${nb}k€'), findsOne);
    expect(find.text('Médiane 518${nb}k€'), findsOne);
    expect(find.text('540${nb}k€'), findsOne);
    expect(find.textContaining('Calculée le 24/09/2026'), findsOne);
    expect(
      find.bySemanticsLabel(
        'Fourchette de 495${nb}000 à 540${nb}000$nb€, '
        'médiane 518${nb}000$nb€',
      ),
      findsOne,
    );
  });

  testWidgets('AI trend without date and with an empty range', (tester) async {
    await pump(
      tester,
      property: const Property(
        id: 'property-id',
        ownerId: 'user-id',
        status: PropertyStatus.submitted,
        aiEstimateLowEur: 500000,
        aiEstimateMedianEur: 500000,
        aiEstimateHighEur: 500000,
      ),
    );
    expect(find.textContaining('Calculée à partir'), findsOne);
  });

  testWidgets('hides the AI trend when a value is missing', (tester) async {
    await pump(
      tester,
      property: const Property(
        id: 'property-id',
        ownerId: 'user-id',
        status: PropertyStatus.submitted,
        aiEstimateLowEur: 495000,
        aiEstimateHighEur: 540000,
      ),
    );
    expect(find.byType(AiEstimateCard), findsNothing);
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
}
