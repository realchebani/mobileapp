import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(RealestyLogo, () {
    test('stroke width adapts to the size', () {
      expect(RealestyLogo.defaultStrokeWidth(20), 5);
      expect(RealestyLogo.defaultStrokeWidth(26), 4.5);
      expect(RealestyLogo.defaultStrokeWidth(48), 4);
      expect(RealestyLogo.defaultStrokeWidth(44), 3.2);
      expect(RealestyLogo.defaultStrokeWidth(72), 3.2);
      expect(RealestyLogo.defaultStrokeWidth(120), 2.6);
    });

    test('wordmark size pairs with the mark size', () {
      expect(RealestyLogo.defaultWordmarkSize(26), 15);
      expect(RealestyLogo.defaultWordmarkSize(40), 20);
      expect(RealestyLogo.defaultWordmarkSize(44), 16);
      expect(RealestyLogo.defaultWordmarkSize(60), 34);
      expect(RealestyLogo.defaultWordmarkSize(72), 34);
      expect(RealestyLogo.horizontalGap(44), 12);
      expect(RealestyLogo.horizontalGap(72), 20);
    });

    test('svg contains the paths, dots and accent', () {
      final svg = RealestyLogo.svg(
        ink: const Color(0xFF141A17),
        accent: const Color(0xFF6CC43A),
        strokeWidth: 3.2,
      );
      expect(svg, contains('M10 42L50 8L90 42V92H10Z'));
      expect(svg, contains('stroke="#141a17"'));
      expect(svg, contains('stroke-width="3.2"'));
      expect('r="4.2"'.allMatches(svg).length, 8);
      expect(svg, contains('fill="#6cc43a" opacity="0.3"'));
    });

    testWidgets('renders the mark alone', (tester) async {
      await tester.pumpRealesty(const RealestyLogo(size: 72));
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('REALESTY'), findsNothing);
      expect(find.bySemanticsLabel('Realesty'), findsOneWidget);
    });

    testWidgets('renders the wordmark lockup', (tester) async {
      await tester.pumpRealesty(
        const RealestyLogo(size: 26, showWordmark: true, wordmarkSize: 15),
      );
      final text = tester.widget<Text>(find.text('REALESTY'));
      expect(text.style?.fontFamily, RealestyFonts.michroma);
      expect(text.style?.fontSize, 15);
      expect(text.style?.color, RealestyColors.light.encre);
    });

    testWidgets('on dark uses white ink', (tester) async {
      await tester.pumpRealesty(
        const RealestyLogo(onDark: true, showWordmark: true, strokeWidth: 3),
      );
      final text = tester.widget<Text>(find.text('REALESTY'));
      expect(text.style?.color, RealestyColors.light.nuitTexte);
      expect(text.style?.fontSize, 16);
      final flex = tester.widget<Flex>(find.byType(Flex));
      expect(flex.direction, Axis.horizontal);
      expect(flex.spacing, 12);
    });

    testWidgets('vertical splash lockup', (tester) async {
      await tester.pumpRealesty(
        const RealestyLogo(
          size: 120,
          showWordmark: true,
          wordmarkSize: 30,
          direction: Axis.vertical,
        ),
      );
      final flex = tester.widget<Flex>(find.byType(Flex));
      expect(flex.direction, Axis.vertical);
      expect(flex.spacing, 28);
      final mark = tester.getRect(find.byType(SvgPicture));
      final word = tester.getRect(find.text('REALESTY'));
      expect(word.top, greaterThanOrEqualTo(mark.bottom + 28));
    });
  });
}
