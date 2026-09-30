import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

const _segments = <RealestySegment<String>>[
  RealestySegment(value: 'a', label: 'Maison', icon: RealestyIcons.home),
  RealestySegment(value: 'b', label: 'Appartement'),
];

void main() {
  const c = RealestyColors.light;

  group(RealestySegmentedControl, () {
    testWidgets('highlights the selected segment and reports taps', (
      tester,
    ) async {
      String? picked;
      await tester.pumpRealesty(
        RealestySegmentedControl<String>(
          segments: _segments,
          selected: 'a',
          onChanged: (v) => picked = v,
        ),
      );
      expect(tester.widget<Text>(find.text('Maison')).style?.color, c.encre);
      expect(
        tester.widget<Text>(find.text('Appartement')).style?.color,
        c.texteDiscret,
      );
      expect(
        tester.getSize(find.byType(RealestySegmentedControl<String>)).height,
        48,
      );
      expect(tester.getSize(find.byType(RealestyPressable).first).height, 48);
      expect(tester.getSize(find.byType(AnimatedContainer).first).height, 40);
      await tester.tap(find.text('Appartement'));
      expect(picked, 'b');
    });

    testWidgets('is disabled without onChanged', (tester) async {
      await tester.pumpRealesty(
        const RealestySegmentedControl<String>(
          segments: _segments,
          selected: 'b',
          onChanged: null,
        ),
      );
      final opacities = tester.widgetList<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacities.every((o) => o.opacity == 0.4), isTrue);
    });
  });
}
