import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

void main() {
  const light = RealestyColors.light;

  group(RealestyColors, () {
    test('light palette matches the spec', () {
      expect(light.encre, const Color(0xFF141A17));
      expect(light.ivoire, const Color(0xFFF6F5EF));
      expect(light.vert, const Color(0xFF6CC43A));
      expect(light.vertTexte, const Color(0xFF2E7D14));
      expect(light.erreur, const Color(0xFFB42318));
      expect(light.lueur, const Color(0xFF8BE05A));
    });

    test('copyWith without arguments keeps every value', () {
      final copy = light.copyWith();
      final lerped = copy.lerp(light, 0.5);
      expect(lerped.encre, light.encre);
      expect(lerped.erreurFond, light.erreurFond);
    });

    test('copyWith overrides every field', () {
      const x = Color(0xFF123456);
      final copy = light.copyWith(
        encre: x,
        encre2: x,
        texteDiscret: x,
        placeholder: x,
        ligne: x,
        bordureCarte: x,
        ivoire: x,
        surface: x,
        surface2: x,
        imagePlaceholder: x,
        vert: x,
        vertTexte: x,
        vertTeinte: x,
        vertLienPresse: x,
        nuit: x,
        nuit2: x,
        nuit3: x,
        lueur: x,
        nuitBordure: x,
        nuitTexteDiscret: x,
        nuitTexte: x,
        essentiel: x,
        essentielFond: x,
        premium: x,
        premiumFond: x,
        expert: x,
        expertFond: x,
        attention: x,
        attentionFond: x,
        erreur: x,
        erreurFond: x,
      );
      expect(copy.encre, x);
      expect(copy.erreurFond, x);
      expect(copy.nuitTexte, x);
    });

    test('lerp interpolates and handles null', () {
      expect(light.lerp(null, 0.5), same(light));
      final black = light.copyWith(encre: const Color(0xFF000000));
      final white = light.copyWith(encre: const Color(0xFFFFFFFF));
      expect(black.lerp(white, 1).encre, const Color(0xFFFFFFFF));
      expect(black.lerp(white, 0).encre, const Color(0xFF000000));
    });

    testWidgets('context.realestyColors reads the theme extension', (
      tester,
    ) async {
      late RealestyColors fromTheme;
      late RealestyColors fallback;
      final custom = light.copyWith(encre: const Color(0xFF010203));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [custom]),
          home: Builder(
            builder: (context) {
              fromTheme = context.realestyColors;
              return Theme(
                data: ThemeData(),
                child: Builder(
                  builder: (context) {
                    fallback = context.realestyColors;
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(fromTheme.encre, const Color(0xFF010203));
      expect(fallback, same(RealestyColors.light));
    });
  });
}
