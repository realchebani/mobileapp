import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/steps/method/plan/plan_review_page.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _nbsp = ' ';

const _reading = PlanReading(
  isFloorPlan: true,
  rooms: [
    PlanRoom(
      name: 'Séjour',
      areaM2: 25.4,
      level: RoomLevel.groundFloor,
      kind: 'livingRoom',
    ),
    PlanRoom(name: 'Chambre 2', kind: 'bedroom'),
    PlanRoom(name: 'Garage', areaM2: 15, kind: 'garage'),
  ],
  printedTotalM2: 40.4,
);

void main() {
  Future<List<PlanReviewResult?>> pump(
    WidgetTester tester, [
    PlanReading reading = _reading,
  ]) async {
    usePhoneSurface();
    final results = <PlanReviewResult?>[];
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              results.add(await showPlanReview(context, reading)),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder field(String label, int index) => find.descendant(
    of: find.widgetWithText(RealestyTextField, label).at(index),
    matching: find.byType(TextField),
  );

  group(PlanReviewPage, () {
    testWidgets('lists the rooms read, each to keep and correct', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Pièces lues sur le plan'), findsOneWidget);
      expect(find.text('Garder Séjour'), findsOneWidget);
      expect(find.text('Extrait d’un document'), findsNWidgets(3));
      expect(find.text('25,4'), findsOneWidget);
      expect(find.text('Ajouter 3 pièces'), findsOneWidget);
      // The sum (40,4) matches the printed total.
      expect(
        find.text('Total imprimé sur le plan$_nbsp: 40,4${_nbsp}m²'),
        findsOneWidget,
      );
    });

    testWidgets('a missing area must be typed, or the line unticked', (
      tester,
    ) async {
      final results = await pump(tester);
      await tap(tester, find.text('Ajouter 3 pièces'));
      expect(
        find.text(
          'Surface non imprimée$_nbsp: saisissez-la ou décochez la ligne.',
        ),
        findsOneWidget,
      );
      expect(results, isEmpty);
      await tester.enterText(field('Surface', 1), '11');
      await tester.pump();
      expect(
        find.textContaining('ne correspond pas au total imprimé'),
        findsOneWidget,
      );
      // An empty name and an area out of range.
      await tester.enterText(field('Nom', 2), ' ');
      await tester.enterText(field('Surface', 2), '900');
      await tester.pump();
      await tap(tester, find.text('Ajouter 3 pièces'));
      expect(results, isEmpty);
      expect(find.textContaining('Indiquez le nom'), findsWidgets);
      await tap(tester, find.text('Garder '));
      await tap(tester, find.text('Ajouter 2 pièces'));
      expect(results.single, isA<PlanReviewAccepted>());
      expect((results.single! as PlanReviewAccepted).rooms, const [
        RoomInput(
          name: 'Séjour',
          level: RoomLevel.groundFloor,
          areaM2: 25.4,
          isMain: true,
        ),
        RoomInput(name: 'Chambre 2', level: null, areaM2: 11, isMain: true),
      ]);
    });

    testWidgets('the level can be corrected', (tester) async {
      final results = await pump(tester);
      await tap(tester, find.text('Garder Chambre 2'));
      await tap(tester, find.text('Garder Garage'));
      expect(find.text('Ajouter 1 pièce'), findsOneWidget);
      await tap(tester, find.text('Rez-de-chaussée'));
      await tap(tester, find.text('Étage').last);
      await tap(tester, find.text('Ajouter 1 pièce'));
      expect(
        (results.single! as PlanReviewAccepted).rooms.single.level,
        RoomLevel.firstFloor,
      );
    });

    testWidgets('nothing kept: nothing to add', (tester) async {
      await pump(tester);
      for (final name in ['Séjour', 'Chambre 2', 'Garage']) {
        await tap(tester, find.text('Garder $name'));
      }
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).onPressed,
        isNull,
      );
      expect(find.text('Aucune pièce à ajouter'), findsOneWidget);
    });

    testWidgets('"Saisir mes pièces" and back', (tester) async {
      final results = await pump(tester);
      await tap(tester, find.text('Saisir mes pièces'));
      expect(results.single, isA<PlanReviewManual>());
      await tap(tester, find.text('go'));
      await tap(tester, find.bySemanticsLabel('Retour'));
      expect(results.last, isNull);
    });

    testWidgets('an image that is not a plan', (tester) async {
      final results = await pump(tester, const PlanReading(isFloorPlan: false));
      expect(find.textContaining('ne ressemble pas à un plan'), findsOneWidget);
      await tap(tester, find.text('Saisir mes pièces'));
      expect(results.single, isA<PlanReviewManual>());
    });

    testWidgets('a plan without readable room', (tester) async {
      await pump(tester, const PlanReading(isFloorPlan: true));
      expect(find.textContaining('Aucune pièce lisible'), findsOneWidget);
    });
  });
}
