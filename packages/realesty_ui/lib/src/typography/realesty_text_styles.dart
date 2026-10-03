import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/typography/realesty_fonts.dart';

/// Realesty type scale. Styles carry no color: they inherit it from the
/// ambient [DefaultTextStyle] / theme unless a widget sets one.
abstract final class RealestyTextStyles {
  // Scale.

  /// Display — Sora 600 32/38.
  static const display = TextStyle(
    fontFamily: RealestyFonts.sora,
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w600,
  );

  /// Titre 1 — Sora 600 26/32.
  static const title1 = TextStyle(
    fontFamily: RealestyFonts.sora,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
  );

  /// Titre 2 — Sora 600 18/24.
  static const title2 = TextStyle(
    fontFamily: RealestyFonts.sora,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );

  /// Chiffre clé — Sora 600 28, line height 1.2, −0.02em.
  static const keyFigure = TextStyle(
    fontFamily: RealestyFonts.sora,
    fontSize: 28,
    height: 1.2,
    letterSpacing: -0.56,
    fontWeight: FontWeight.w600,
  );

  /// Corps — Hanken Grotesk 400 16/24.
  static const body = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  /// Corps S — Hanken Grotesk 400 14/20.
  static const bodySmall = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Libellé — Hanken Grotesk 600 13 (field labels).
  static const label = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// Légende — Hanken Grotesk 700 12/16, 0.08em. Render the text in
  /// UPPERCASE (Flutter has no text-transform).
  static const caption = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.96,
    fontWeight: FontWeight.w700,
  );

  // Components.

  /// Button label — Hanken Grotesk 600 16, line height 1.2.
  static const button = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  /// Segment and selected chip label — 14/600.
  static const segment = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// Unselected chip label — 14/500.
  static const chip = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// List item title — 15/600, line height 1.35.
  static const listTitle = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  /// List item subtitle — 13, line height 1.4.
  static const listSubtitle = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  /// Chat bubble — 15, line height 1.5.
  static const bubble = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// Badge — 12/700.
  static const badge = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  /// Provenance tag — 11/700.
  static const tag = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  /// Tab bar label — 11/600 (700 when active).
  static const tabLabel = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Card price — Sora 20/600, −0.02em.
  static const cardPrice = TextStyle(
    fontFamily: RealestyFonts.sora,
    fontSize: 20,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w600,
  );

  /// Counter value — Sora 18/600.
  static const stepperValue = TextStyle(
    fontFamily: RealestyFonts.sora,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  /// Inline banner text — 13, line height 1.45.
  static const banner = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  /// Field error message — 13/500.
  static const fieldError = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// Checkbox label — 14, line height 1.45.
  static const checkboxLabel = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  /// Snackbar message — 14/500.
  static const snackBar = TextStyle(
    fontFamily: RealestyFonts.hankenGrotesk,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// Michroma wordmark ("REALESTY") at [fontSize], letter spacing 0.16em,
  /// line height 1.
  static TextStyle wordmark(double fontSize) => TextStyle(
    fontFamily: RealestyFonts.michroma,
    fontSize: fontSize,
    height: 1,
    letterSpacing: fontSize * 0.16,
    fontWeight: FontWeight.w400,
  );

  /// Material [TextTheme] mapped on the Realesty scale.
  static const textTheme = TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: display,
    headlineLarge: display,
    headlineMedium: title1,
    headlineSmall: keyFigure,
    titleLarge: title2,
    titleMedium: listTitle,
    titleSmall: label,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: bodySmall,
    labelLarge: button,
    labelMedium: label,
    labelSmall: caption,
  );
}
