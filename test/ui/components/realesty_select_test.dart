import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

const _options = <RealestySelectOption<int>>[
  RealestySelectOption(value: 1, label: 'Maison'),
  RealestySelectOption(value: 2, label: 'Appartement'),
];

void main() {
  const c = RealestyColors.light;

  group(RealestySelect, () {
    testWidgets('shows the hint then opens a sheet to pick', (tester) async {
      int? picked;
      await tester.pumpRealesty(
        RealestySelect<int>(
          label: 'Type de bien',
          hint: 'Choisir',
          leadingIcon: RealestyIcons.home,
          options: _options,
          onChanged: (value) => picked = value,
        ),
      );
      final hint = tester.widget<Text>(find.text('Choisir'));
      expect(hint.style?.color, c.placeholder);
      await tester.tap(find.text('Choisir'));
      await tester.pumpAndSettle();
      expect(find.text('Type de bien'), findsNWidgets(2));
      await tester.tap(find.text('Appartement'));
      await tester.pumpAndSettle();
      expect(picked, 2);
    });

    testWidgets('shows the selected value with a check in the sheet', (
      tester,
    ) async {
      int? picked;
      await tester.pumpRealesty(
        RealestySelect<int>(
          label: 'Type',
          sheetTitle: 'Quel type ?',
          value: 1,
          options: _options,
          onChanged: (value) => picked = value,
        ),
      );
      expect(tester.widget<Text>(find.text('Maison')).style?.color, c.encre);
      await tester.tap(find.text('Maison'));
      await tester.pumpAndSettle();
      expect(find.text('Quel type ?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(RealestyIcon),
        ),
        findsOneWidget,
      );
      final rows = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.constraints?.minHeight == 52,
              ),
            ),
          )
          .map((w) => (w.decoration! as BoxDecoration).border)
          .toList();
      expect(rows.first, isNotNull);
      expect(rows.last, isNull);
      // Dismiss without picking.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });

    testWidgets('is disabled without onChanged', (tester) async {
      await tester.pumpRealesty(
        const RealestySelect<int>(
          label: 'Type',
          options: _options,
          onChanged: null,
        ),
      );
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
