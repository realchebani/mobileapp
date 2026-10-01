import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/widgets/room_sheet.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _nbsp = ' ';

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(TextField),
);

void main() {
  late RoomSheetResult? result;
  late bool closed;

  Future<void> open(
    WidgetTester tester, {
    RoomInput? initial,
    RoomLevel defaultLevel = RoomLevel.groundFloor,
    List<String> otherNames = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(390, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    result = null;
    closed = false;
    await tester.pumpApp(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              result = await showRoomSheet(
                context,
                initial: initial,
                defaultLevel: defaultLevel,
                otherNames: otherNames,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group(RoomSheet, () {
    testWidgets('adds a room', (tester) async {
      await open(tester, defaultLevel: RoomLevel.firstFloor);

      expect(find.text('Ajouter une pièce'), findsOneWidget);
      expect(find.text('Étage'), findsOneWidget);
      expect(find.text('Supprimer cette pièce'), findsNothing);

      await tester.tap(find.text('Séjour'));
      await tester.pump();
      expect(
        tester.widget<RealestyCheckbox>(find.byType(RealestyCheckbox)).value,
        isTrue,
      );
      await tester.enterText(_field('Surface'), '38,5');
      await tester.tap(find.byType(RealestySelect<RoomLevel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rez-de-chaussée').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RealestySelect<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parquet chêne').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RealestySelect<Glazing?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Double').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RealestyCheckbox));
      await tester.pump();

      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(
        (result! as RoomSheetSaved).room,
        const RoomInput(
          name: 'Séjour',
          level: RoomLevel.groundFloor,
          areaM2: 38.5,
          floorCovering: 'parquet_chene',
          glazing: Glazing.double,
        ),
      );
    });

    testWidgets('shows the errors once submitted and refreshes them', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Indiquez le nom de la pièce.'), findsNothing);

      await tester.tap(find.text('Ajouter'));
      await tester.pump();
      expect(find.text('Indiquez le nom de la pièce.'), findsOneWidget);
      expect(find.text('Indiquez la surface de la pièce.'), findsOneWidget);

      await tester.enterText(_field('Nom'), 'Véranda');
      await tester.enterText(_field('Surface'), '0,2');
      await tester.pump();
      expect(find.text('Indiquez le nom de la pièce.'), findsNothing);
      expect(
        find.text('La surface doit être comprise entre 0,5 et 500${_nbsp}m².'),
        findsOneWidget,
      );
      // Too many digits or decimals are not typed.
      await tester.enterText(_field('Surface'), '1000');
      await tester.enterText(_field('Surface'), '12,345');
      await tester.pump();
      expect(find.text('0,2'), findsOneWidget);

      await tester.enterText(_field('Surface'), '12.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        (result! as RoomSheetSaved).room,
        const RoomInput(
          name: 'Véranda',
          level: RoomLevel.groundFloor,
          areaM2: 12.5,
        ),
      );
    });

    testWidgets('a plain "Chambre" counts as the first bedroom', (
      tester,
    ) async {
      await open(tester, otherNames: ['Chambre']);
      await tester.tap(find.text('Chambre'));
      await tester.pump();
      expect(find.text('Chambre 2'), findsOneWidget);
    });

    testWidgets('scrolls to the first error', (tester) async {
      await open(tester);
      tester.view.physicalSize = const Size(390, 500);
      await tester.pumpAndSettle();

      await tester.enterText(_field('Nom'), 'Cave');
      await tester.dragUntilVisible(
        find.text('Ajouter'),
        find.byType(SingleChildScrollView).last,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('Indiquez la surface de la pièce.'), findsOneWidget);
      expect(tester.getTopLeft(_field('Surface')).dy, inInclusiveRange(0, 500));

      await tester.enterText(_field('Nom'), '');
      await tester.dragUntilVisible(
        find.text('Ajouter'),
        find.byType(SingleChildScrollView).last,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_field('Nom')).dy, inInclusiveRange(0, 500));
    });

    testWidgets('numbers the bedrooms and clears the name for "Autre"', (
      tester,
    ) async {
      await open(tester, otherNames: ['Chambre 4', 'Chambrette', 'Chambre']);

      await tester.tap(find.text('Chambre'));
      await tester.pump();
      expect(find.text('Chambre 5'), findsOneWidget);

      await tester.tap(find.text('Autre'));
      await tester.pump();
      expect(find.text('Chambre 5'), findsNothing);
      expect(
        tester.widget<RealestyCheckbox>(find.byType(RealestyCheckbox)).value,
        isFalse,
      );
    });

    testWidgets('edits a room and keeps an unknown covering', (tester) async {
      await open(
        tester,
        initial: const RoomInput(
          name: 'Séjour',
          level: null,
          areaM2: 38,
          floorCovering: 'Marbre',
          glazing: Glazing.triple,
          isMain: true,
        ),
      );

      expect(find.text('Modifier la pièce'), findsOneWidget);
      expect(find.text('38'), findsOneWidget);
      expect(find.text('Marbre'), findsOneWidget);
      expect(find.text('Non précisé'), findsOneWidget);

      await tester.tap(find.byType(RealestySelect<Glazing?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non précisé').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(
        (result! as RoomSheetSaved).room,
        const RoomInput(
          name: 'Séjour',
          level: null,
          areaM2: 38,
          floorCovering: 'Marbre',
          isMain: true,
        ),
      );
    });

    testWidgets('deletes a room', (tester) async {
      await open(
        tester,
        initial: const RoomInput(
          name: 'WC',
          level: RoomLevel.groundFloor,
          areaM2: 1.6,
        ),
      );

      await tester.tap(find.text('Supprimer cette pièce'));
      await tester.pumpAndSettle();

      expect(result, isA<RoomSheetDeleted>());
    });
  });
}
