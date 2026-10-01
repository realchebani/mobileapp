import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group(SelectableCard, () {
    testWidgets('renders both states and reports taps', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        SelectableCardGrid(
          children: [
            SelectableCard(
              icon: RealestyIcons.user,
              title: 'Unique propriétaire',
              selected: false,
              onTap: () => taps++,
            ),
            SelectableCard(
              icon: RealestyIcons.users,
              title: 'Plusieurs propriétaires',
              subtitle: 'Couple, indivision, héritage…',
              selected: true,
              onTap: () {},
            ),
            const SelectableCard(
              icon: RealestyIcons.land,
              title: 'Terrain',
              selected: false,
              onTap: null,
            ),
          ],
        ),
      );

      expect(find.text('Couple, indivision, héritage…'), findsOneWidget);
      // Selected card: check mark in the radio dot.
      expect(
        find.descendant(
          of: find.widgetWithText(SelectableCard, 'Plusieurs propriétaires'),
          matching: find.byWidgetPredicate(
            (w) => w is RealestyIcon && w.icon == RealestyIcons.check,
          ),
        ),
        findsOneWidget,
      );
      // Cards of a row share its height.
      expect(
        tester.getSize(find.byType(SelectableCard).at(0)).height,
        tester.getSize(find.byType(SelectableCard).at(1)).height,
      );

      await tester.tap(find.text('Unique propriétaire'));
      expect(taps, 1);
      expect(
        tester.getSemantics(find.text('Plusieurs propriétaires')),
        isSemantics(isSelected: true, isButton: true),
      );
    });

    testWidgets('grid accepts a custom spacing', (tester) async {
      await tester.pumpApp(
        const SelectableCardGrid(spacing: 10, children: [SizedBox()]),
      );
      expect(tester.widget<Column>(find.byType(Column).first).spacing, 10);
    });
  });
}
