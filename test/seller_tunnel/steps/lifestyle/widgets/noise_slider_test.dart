import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/noise_slider.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('NoiseSlider', () {
    late List<int> changes;

    setUp(() => changes = []);

    Future<void> pump(
      WidgetTester tester, {
      int? value,
      bool enabled = true,
    }) async {
      usePhoneSurface();
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 300,
            child: NoiseSlider(
              value: value,
              onChanged: enabled ? changes.add : null,
              semanticLabel: 'Bruit',
              semanticValue: 'valeur',
              minLabel: 'Très calme',
              maxLabel: 'Très bruyant',
            ),
          ),
        ),
      );
    }

    Offset at(WidgetTester tester, int level) {
      final rect = tester.getRect(find.byType(NoiseSlider));
      return Offset(
        rect.left + 14 + (rect.width - 28) * NoiseSlider.fractionOf(level),
        rect.top + 18,
      );
    }

    testWidgets('sets the tapped level', (tester) async {
      await pump(tester, value: 3);
      await tester.tapAt(at(tester, 7));
      // The current level is not reported again.
      await tester.tapAt(at(tester, 3));
      expect(changes, [7]);
      expect(find.text('Très calme'), findsOneWidget);
      expect(find.text('Très bruyant'), findsOneWidget);
    });

    testWidgets('follows a drag, clamped to the track', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(at(tester, 2));
      await gesture.moveBy(const Offset(-200, 0));
      await gesture.moveBy(const Offset(600, 0));
      await gesture.up();
      expect(changes.last, 10);
      expect(changes, containsAllInOrder([1, 10]));
    });

    testWidgets('rests on 5 with a neutral ring until answered', (
      tester,
    ) async {
      await pump(tester);
      final thumb = tester.widget<Container>(
        find.byKey(const Key('noiseSlider_thumb')),
      );
      final border = (thumb.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, isNot(NoiseSlider.colorAt(0.5)));
    });

    testWidgets('is adjustable with assistive technologies', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      final node = find.semantics.byLabel('Bruit');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Bruit')),
        isSemantics(increasedValue: '5/10', decreasedValue: '5/10'),
      );
      // Unanswered: the first step answers the resting value.
      tester.semantics.performAction(node, SemanticsAction.increase);
      tester.semantics.performAction(node, SemanticsAction.decrease);
      expect(changes, [5, 5]);
      semantics.dispose();
    });

    testWidgets('steps by one from an answer', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, value: 4);
      final node = find.semantics.byLabel('Bruit');
      tester.semantics.performAction(node, SemanticsAction.increase);
      tester.semantics.performAction(node, SemanticsAction.decrease);
      expect(changes, [5, 3]);
      semantics.dispose();
    });

    testWidgets('cannot go past the ends', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, value: 10);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Bruit')),
        isSemantics(hasIncreaseAction: false, hasDecreaseAction: true),
      );
      await pump(tester, value: 1);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Bruit')),
        isSemantics(hasIncreaseAction: true, hasDecreaseAction: false),
      );
      semantics.dispose();
    });

    testWidgets('ignores input when disabled', (tester) async {
      await pump(tester, value: 3, enabled: false);
      await tester.tapAt(at(tester, 7));
      expect(changes, isEmpty);
    });
  });

  test('colorAt follows the gradient', () {
    expect(NoiseSlider.colorAt(0), NoiseSlider.trackColors.first);
    expect(NoiseSlider.colorAt(0.52), NoiseSlider.trackColors[2]);
    expect(NoiseSlider.colorAt(1), NoiseSlider.trackColors.last);
    expect(NoiseSlider.colorAt(2), NoiseSlider.trackColors.last);
  });
}
