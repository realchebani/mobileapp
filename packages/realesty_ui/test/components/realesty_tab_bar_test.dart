import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(RealestyTabBar, () {
    testWidgets('marks the current tab, shows badges and reports taps', (
      tester,
    ) async {
      final tapped = <int>[];
      await tester.pumpRealesty(
        RealestyTabBar(
          semanticLabel: 'Navigation principale',
          currentIndex: 1,
          onTap: tapped.add,
          tabs: const [
            RealestyTab(icon: RealestyIcons.home, label: 'Mon bien'),
            RealestyTab(
              icon: RealestyIcons.calendar,
              label: 'Visites',
              badge: true,
            ),
          ],
        ),
      );

      final selected = tester.widget<Text>(find.text('Visites'));
      expect(selected.style?.color, c.encre);
      expect(selected.style?.fontWeight, FontWeight.w700);
      final other = tester.widget<Text>(find.text('Mon bien'));
      expect(other.style?.color, c.texteDiscret);
      expect(other.style?.fontWeight, FontWeight.w600);
      expect(find.bySemanticsLabel('Navigation principale'), findsOneWidget);
      // One unread dot (red, bordered).
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              (widget.decoration as BoxDecoration?)?.color == c.erreur,
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Mon bien'));
      await tester.tap(find.text('Visites'));
      expect(tapped, [0, 1]);
    });
  });
}
