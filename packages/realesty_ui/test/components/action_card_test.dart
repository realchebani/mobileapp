import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  BoxDecoration cardDecoration(WidgetTester tester) =>
      tester
              .widget<Container>(
                find
                    .descendant(
                      of: find.byType(ActionCard),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;

  group(ActionCard, () {
    testWidgets('accent card with a subtitle', (tester) async {
      var taps = 0;
      await tester.pumpRealesty(
        ActionCard(
          icon: RealestyIcons.trending,
          title: 'Mettre mon bien en vente',
          subtitle: 'Dès 1 %',
          variant: ActionCardVariant.accent,
          onPressed: () => taps++,
        ),
      );
      expect(cardDecoration(tester).color, c.vert);
      expect(find.text('Dès 1 %'), findsOneWidget);
      await tester.tap(find.byType(ActionCard));
      expect(taps, 1);
    });

    testWidgets('neutral card without subtitle', (tester) async {
      await tester.pumpRealesty(
        const ActionCard(
          icon: RealestyIcons.clock,
          title: 'Suivi',
          onPressed: null,
        ),
      );
      expect(cardDecoration(tester).color, c.surface);
      expect(find.bySemanticsLabel('Suivi'), findsOneWidget);
    });
  });
}
