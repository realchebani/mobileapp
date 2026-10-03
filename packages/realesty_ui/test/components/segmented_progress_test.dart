import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(SegmentedProgress, () {
    testWidgets('colors completed segments', (tester) async {
      await tester.pumpRealesty(
        const SizedBox(
          width: 300,
          child: SegmentedProgress(total: 4, completed: 1),
        ),
      );
      final colors = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((w) => (w.decoration! as BoxDecoration).color)
          .toList();
      expect(colors, [c.vertTexte, c.ligne, c.ligne, c.ligne]);
      expect(find.bySemanticsLabel('1 / 4'), findsOneWidget);
    });

    testWidgets('uses the custom semantic label', (tester) async {
      await tester.pumpRealesty(
        const SegmentedProgress(
          total: 3,
          completed: 3,
          semanticLabel: 'Étape 3 sur 3',
        ),
      );
      expect(find.bySemanticsLabel('Étape 3 sur 3'), findsOneWidget);
    });
  });
}
