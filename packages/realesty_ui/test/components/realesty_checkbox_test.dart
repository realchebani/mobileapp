import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  BoxDecoration box(WidgetTester tester) =>
      tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .decoration!
          as BoxDecoration;

  group(RealestyCheckbox, () {
    testWidgets('unchecked toggles to true when the row is tapped', (
      tester,
    ) async {
      bool? value;
      await tester.pumpRealesty(
        RealestyCheckbox(
          value: false,
          label: 'Recevoir les actualités',
          onChanged: (v) => value = v,
        ),
      );
      expect(box(tester).color, c.surface);
      expect(find.byType(RealestyIcon), findsNothing);
      await tester.tap(find.text('Recevoir les actualités'));
      expect(value, isTrue);
      expect(
        tester.getSize(find.byType(RealestyCheckbox)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('checked shows the check and toggles to false', (tester) async {
      bool? value;
      await tester.pumpRealesty(
        RealestyCheckbox(value: true, label: 'OK', onChanged: (v) => value = v),
      );
      expect(box(tester).color, c.encre);
      expect(find.byType(RealestyIcon), findsOneWidget);
      await tester.tap(find.text('OK'));
      expect(value, isFalse);
    });

    testWidgets('rich label links handle their own taps', (tester) async {
      var linkTaps = 0;
      bool? value;
      final recognizer = TapGestureRecognizer()..onTap = () => linkTaps++;
      addTearDown(recognizer.dispose);
      await tester.pumpRealesty(
        Builder(
          builder: (context) => RealestyCheckbox(
            value: false,
            onChanged: (v) => value = v,
            richLabel: TextSpan(
              text: 'CGU',
              style: RealestyCheckbox.linkStyle(context),
              recognizer: recognizer,
            ),
          ),
        ),
      );
      await tester.tapOnText(find.textRange.ofSubstring('CGU'));
      expect(linkTaps, 1);
      expect(value, isNull);
    });

    testWidgets('disabled ignores taps', (tester) async {
      await tester.pumpRealesty(
        const RealestyCheckbox(value: false, label: 'Off', onChanged: null),
      );
      await tester.tap(find.text('Off'));
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.4);
    });
  });
}
