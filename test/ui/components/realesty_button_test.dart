import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(RealestyButton),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  const c = RealestyColors.light;

  group(RealestyButton, () {
    testWidgets('primary renders label, height 52 and handles taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpRealesty(
        RealestyButton(label: 'Continuer', onPressed: () => taps++),
      );
      expect(tester.getSize(find.byType(RealestyButton)).height, 52);
      expect(_decoration(tester).color, c.encre);
      final text = tester.widget<Text>(find.text('Continuer'));
      expect(text.style?.color, c.surface);
      await tester.tap(find.byType(RealestyButton));
      expect(taps, 1);
    });

    testWidgets('variants use their colors', (tester) async {
      final expected = {
        RealestyButtonVariant.accent: (c.vert, c.encre),
        RealestyButtonVariant.secondary: (c.surface, c.encre),
        RealestyButtonVariant.text: (Colors.transparent, c.vertTexte),
        RealestyButtonVariant.destructive: (c.erreur, c.surface),
      };
      for (final MapEntry(key: variant, value: (bg, fg)) in expected.entries) {
        await tester.pumpRealesty(
          RealestyButton(
            label: variant.name,
            variant: variant,
            leadingIcon: RealestyIcons.mic,
            height: 56,
            expand: false,
            onPressed: () {},
          ),
        );
        expect(_decoration(tester).color, bg);
        expect(tester.widget<Text>(find.text(variant.name)).style?.color, fg);
        expect(
          tester.widget<RealestyIcon>(find.byType(RealestyIcon)).color,
          fg,
        );
        expect(tester.getSize(find.byType(RealestyButton)).height, 56);
      }
    });

    testWidgets('shows a trailing icon after the label', (tester) async {
      await tester.pumpRealesty(
        RealestyButton(
          label: 'Envoyer',
          variant: RealestyButtonVariant.accent,
          trailingIcon: RealestyIcons.chevronRight,
          onPressed: () {},
        ),
      );
      final icon = tester.widget<RealestyIcon>(find.byType(RealestyIcon));
      expect(icon.icon, RealestyIcons.chevronRight);
      expect(icon.color, c.encre);
      expect(
        tester.getTopLeft(find.byType(RealestyIcon)).dx,
        greaterThan(tester.getTopRight(find.text('Envoyer')).dx),
      );
    });

    testWidgets('loading shows a spinner and ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpRealesty(
        RealestyButton(
          label: 'Envoyer',
          isLoading: true,
          onPressed: () => taps++,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Envoyer'), findsNothing);
      expect(
        find.bySemanticsLabel('Envoyer, chargement en cours'),
        findsOneWidget,
      );
      await tester.tap(find.byType(RealestyButton));
      expect(taps, 0);
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 1);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpRealesty(
        const RealestyButton(label: 'Off', onPressed: null),
      );
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.4);
    });
  });
}
