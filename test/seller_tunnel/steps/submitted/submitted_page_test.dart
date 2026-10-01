import 'package:auth_repository/auth_repository.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/data/notification_preference_store.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/ai_estimate_card.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/dossier_summary_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_timeline.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/helpers.dart';

const nb = '\u00a0';

class _MockStore extends Mock implements NotificationPreferenceStore;

const _owner = PropertyOwner(
  propertyId: 'property-id',
  position: 1,
  firstName: 'Sophie',
  lastName: 'Durand',
  email: 'sophie.durand@email.fr',
);

void main() {
  late _MockStore store;

  setUp(() {
    store = _MockStore();
    when(() => store.read(any())).thenAnswer((_) async => null);
    when(() => store.write(any(), enabled: any(named: 'enabled')))
        .thenAnswer((_) async {});
  });

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
      SubmittedPage(notificationStore: store),
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
    expect(find.text('Consultable ici et envoyé par e-mail'), findsOne);
    expect(nodeStates(tester), [
      TimelineNodeState.done,
      TimelineNodeState.current,
      TimelineNodeState.todo,
    ]);
    expect(find.byType(AiEstimateCard), findsNothing);
    expect(find.text('Et par e-mail à sophie.durand@email.fr'), findsOne);
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
    expect(find.byType(Switch), findsOne);
  });

  testWidgets('certified: every step is done, no switch nor AI trend', (
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
    expect(find.byType(Switch), findsNothing);
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
    expect(find.byType(Switch), findsNothing);
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

  testWidgets('without owner: generic thanks and account e-mail', (
    tester,
  ) async {
    final appBloc = MockAppBloc();
    when(() => appBloc.state).thenReturn(
      const AppState.authenticated(
        AuthUser(id: 'user-id', email: 'compte@email.fr'),
      ),
    );
    await pump(tester, owners: const [], appBloc: appBloc);
    expect(find.text('Merci, votre dossier est complet'), findsOne);
    expect(find.text('Et par e-mail à compte@email.fr'), findsOne);
  });

  testWidgets('without any e-mail: no e-mail line', (tester) async {
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
    expect(find.textContaining('Et par e-mail'), findsNothing);
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

  testWidgets('the switch starts from the saved choice and saves changes', (
    tester,
  ) async {
    when(() => store.read('property-id')).thenAnswer((_) async => false);
    await pump(
      tester,
      property: const Property(
        id: 'property-id',
        ownerId: 'user-id',
        status: PropertyStatus.inReview,
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    verify(() => store.write('property-id', enabled: true)).called(1);
  });

  group('open dossier', () {
    const submitted = Property(
      id: 'property-id',
      ownerId: 'user-id',
      status: PropertyStatus.submitted,
    );

    MockSellerTunnelCubit cubitSaving(SellerTunnelSaveStatus result) {
      var state = const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: submitted,
        owners: [_owner],
      );
      final cubit = mockSellerTunnelCubit(state);
      when(() => cubit.state).thenAnswer((_) => state);
      when(() => cubit.save(any())).thenAnswer((_) async {
        state = state.copyWith(saveStatus: result);
      });
      return cubit;
    }

    testWidgets('the switch also saves notify_push', (tester) async {
      final cubit = cubitSaving(SellerTunnelSaveStatus.success);
      await pump(tester, cubit: cubit);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      verify(() => cubit.save({PropertyColumns.notifyPush: false})).called(1);
      verify(() => store.write('property-id', enabled: false)).called(1);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('the switch reverts when notify_push cannot be saved', (
      tester,
    ) async {
      final cubit = cubitSaving(SellerTunnelSaveStatus.failure);
      await pump(tester, cubit: cubit);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      verifyNever(() => store.write(any(), enabled: any(named: 'enabled')));
    });
  });

  testWidgets('a locked dossier keeps the choice on the device only', (
    tester,
  ) async {
    final cubit = mockSellerTunnelCubit(
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'property-id',
          ownerId: 'user-id',
          status: PropertyStatus.inReview,
        ),
      ),
    );
    await pump(tester, cubit: cubit);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    verifyNever(() => cubit.save(any()));
    verify(() => store.write('property-id', enabled: false)).called(1);
  });

  testWidgets('"Retour à mon dossier" opens the seller space', (tester) async {
    final goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    await pump(tester, goRouter: goRouter);
    await tester.ensureVisible(find.text('Retour à mon dossier'));
    await tester.tap(find.text('Retour à mon dossier'));
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

  testWidgets('uses the device store by default', (tester) async {
    SharedPreferences.setMockInitialValues({
      'submitted.notify.property-id': false,
    });
    await tester.pumpTunnelPage(
      const SubmittedPage(),
      sellerTunnelCubit: mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            status: PropertyStatus.inReview,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
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
