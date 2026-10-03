import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  BoxDecoration decoration(WidgetTester tester) =>
      tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .decoration!
          as BoxDecoration;

  group(RealestyChoiceChip, () {
    testWidgets('selected chip shows a check on a green tint', (tester) async {
      bool? value;
      await tester.pumpRealesty(
        RealestyChoiceChip(
          label: 'Jardin',
          selected: true,
          onSelected: (v) => value = v,
        ),
      );
      expect(decoration(tester).color, c.vertTeinte);
      expect(
        tester.widget<RealestyIcon>(find.byType(RealestyIcon)).icon,
        RealestyIcons.check,
      );
      expect(
        tester.widget<Text>(find.text('Jardin')).style?.fontWeight,
        FontWeight.w600,
      );
      expect(tester.getSize(find.byType(RealestyChoiceChip)).height, 44);
      await tester.tap(find.text('Jardin'));
      expect(value, isFalse);
    });

    testWidgets('unselected chip is white with its icon', (tester) async {
      bool? value;
      await tester.pumpRealesty(
        RealestyChoiceChip(
          label: 'Garage',
          icon: RealestyIcons.car,
          selected: false,
          onSelected: (v) => value = v,
        ),
      );
      expect(decoration(tester).color, c.surface);
      expect(
        tester.widget<Text>(find.text('Garage')).style?.fontWeight,
        FontWeight.w500,
      );
      await tester.tap(find.text('Garage'));
      expect(value, isTrue);
    });

    testWidgets('without icon and disabled', (tester) async {
      await tester.pumpRealesty(
        const RealestyChoiceChip(
          label: 'Off',
          selected: false,
          onSelected: null,
        ),
      );
      expect(find.byType(RealestyIcon), findsNothing);
    });
  });
}
