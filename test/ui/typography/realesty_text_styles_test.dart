import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

void main() {
  group(RealestyTextStyles, () {
    test('scale', () {
      expect(RealestyTextStyles.display.fontFamily, RealestyFonts.sora);
      expect(RealestyTextStyles.display.fontSize, 32);
      expect(RealestyTextStyles.title1.fontSize, 26);
      expect(RealestyTextStyles.title2.fontSize, 18);
      expect(RealestyTextStyles.keyFigure.letterSpacing, closeTo(-0.56, 1e-9));
      expect(RealestyTextStyles.body.height, 1.5);
      expect(
        RealestyTextStyles.bodySmall.fontFamily,
        RealestyFonts.hankenGrotesk,
      );
      expect(RealestyTextStyles.label.fontWeight, FontWeight.w600);
      expect(RealestyTextStyles.caption.fontWeight, FontWeight.w700);
    });

    test('wordmark uses Michroma with 0.16em tracking', () {
      final style = RealestyTextStyles.wordmark(30);
      expect(style.fontFamily, RealestyFonts.michroma);
      expect(style.letterSpacing, closeTo(4.8, 1e-9));
      expect(style.height, 1);
    });

    test('text theme maps the scale', () {
      const theme = RealestyTextStyles.textTheme;
      expect(theme.bodyMedium, RealestyTextStyles.body);
      expect(theme.titleLarge, RealestyTextStyles.title2);
      expect(theme.labelLarge, RealestyTextStyles.button);
    });
  });
}
