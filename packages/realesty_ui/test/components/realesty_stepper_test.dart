import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(RealestyStepper, () {
    testWidgets('increments and decrements', (tester) async {
      final values = <int>[];
      await tester.pumpRealesty(
        RealestyStepper(
          title: 'Chambres',
          subtitle: 'Plus de 9 m²',
          value: 2,
          max: 5,
          onChanged: values.add,
        ),
      );
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Plus de 9 m²'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Augmenter Chambres'));
      await tester.tap(find.bySemanticsLabel('Diminuer Chambres'));
      expect(values, [3, 1]);
    });

    testWidgets('clamps at min and max', (tester) async {
      final values = <int>[];
      await tester.pumpRealesty(
        RealestyStepper(
          title: 'Niveaux',
          value: 1,
          min: 1,
          max: 1,
          onChanged: values.add,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Augmenter Niveaux'));
      await tester.tap(find.bySemanticsLabel('Diminuer Niveaux'));
      expect(values, isEmpty);
    });

    testWidgets('unbounded max and disabled', (tester) async {
      final values = <int>[];
      await tester.pumpRealesty(
        RealestyStepper(title: 'Pièces', value: 99, onChanged: values.add),
      );
      await tester.tap(find.bySemanticsLabel('Augmenter Pièces'));
      expect(values, [100]);
      await tester.pumpRealesty(
        const RealestyStepper(title: 'Pièces', value: 1, onChanged: null),
      );
      final opacities = tester.widgetList<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacities.every((o) => o.opacity == 0.4), isTrue);
    });
  });
}
