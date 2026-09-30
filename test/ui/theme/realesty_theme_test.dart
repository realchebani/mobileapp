import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

void main() {
  group('realestyTheme', () {
    final theme = realestyTheme();
    const c = RealestyColors.light;

    test('is Material 3 with the Realesty colors', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, c.ivoire);
      expect(theme.colorScheme.primary, c.encre);
      expect(theme.colorScheme.onPrimary, c.surface);
      expect(theme.colorScheme.secondary, c.vertTexte);
      expect(theme.colorScheme.surface, c.surface);
      expect(theme.colorScheme.error, const Color(0xFFB42318));
      expect(theme.extension<RealestyColors>(), same(c));
      expect(theme.textTheme.bodyMedium?.color, c.encre);
      expect(theme.textTheme.bodyMedium?.fontSize, 16);
    });

    test('snackbars float with the spec styling', () {
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.backgroundColor, c.encre);
      expect(theme.snackBarTheme.insetPadding, const EdgeInsets.all(20));
    });

    test('input decoration covers focus and error states', () {
      final input = theme.inputDecorationTheme;
      final focused = input.focusedBorder! as OutlineInputBorder;
      final error = input.errorBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, c.encre);
      expect(focused.borderSide.width, 1.5);
      expect(error.borderSide.color, c.erreur);
    });

    test('checkbox and switch resolve their states', () {
      const selected = {WidgetState.selected};
      const idle = <WidgetState>{};
      final checkbox = theme.checkboxTheme;
      expect(checkbox.fillColor!.resolve(selected), c.encre);
      expect(checkbox.fillColor!.resolve(idle), c.surface);
      expect(
        WidgetStateProperty.resolveAs(checkbox.side, selected)!.color,
        c.encre,
      );
      expect(
        WidgetStateProperty.resolveAs(checkbox.side, idle)!.color,
        c.ligne,
      );
      final track = theme.switchTheme.trackColor!;
      expect(track.resolve(selected), c.vertTexte);
      expect(track.resolve(idle), c.ligne);
    });

    test('bottom sheets are elevated with a soft encre shadow', () {
      expect(theme.bottomSheetTheme.modalElevation, 12);
      expect(
        theme.bottomSheetTheme.shadowColor,
        c.encre.withValues(alpha: 0.18),
      );
    });

    test('progress indicators use the brand green', () {
      expect(theme.progressIndicatorTheme.color, c.vert);
      expect(theme.progressIndicatorTheme.linearTrackColor, c.bordureCarte);
    });

    testWidgets('material buttons render with the theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('A')),
                OutlinedButton(onPressed: () {}, child: const Text('B')),
                TextButton(onPressed: () {}, child: const Text('C')),
              ],
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(FilledButton)).height, 52);
    });
  });
}
