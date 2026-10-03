import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

double _opacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main() {
  group(RealestyPressable, () {
    testWidgets('dims while pressed and calls onPressed', (tester) async {
      var taps = 0;
      await tester.pumpRealesty(
        RealestyPressable(
          onPressed: () => taps++,
          child: const SizedBox(width: 100, height: 50, child: Text('Tap')),
        ),
      );
      expect(_opacity(tester), 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Tap')),
      );
      await tester.pump();
      expect(_opacity(tester), RealestyPressable.pressedOpacity);
      await gesture.up();
      await tester.pump();
      expect(_opacity(tester), 1);
      expect(taps, 1);
    });

    testWidgets('resets when the tap is cancelled', (tester) async {
      await tester.pumpRealesty(
        RealestyPressable(
          onPressed: () {},
          child: const SizedBox(width: 100, height: 50, child: Text('Tap')),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Tap')),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 300));
      await gesture.cancel();
      await tester.pump();
      expect(_opacity(tester), 1);
    });

    testWidgets('disabled is dimmed unless showDisabled is false', (
      tester,
    ) async {
      await tester.pumpRealesty(const RealestyPressable(child: Text('Off')));
      expect(_opacity(tester), RealestyPressable.disabledOpacity);
      await tester.pumpRealesty(
        const RealestyPressable(showDisabled: false, child: Text('Off')),
      );
      expect(_opacity(tester), 1);
    });

    testWidgets('exposes button semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpRealesty(
        RealestyPressable(
          onPressed: () {},
          semanticLabel: 'Label',
          selected: true,
          child: const Text('Visible'),
        ),
      );
      expect(
        tester.getSemantics(find.byType(RealestyPressable)),
        matchesSemantics(
          label: 'Label',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
