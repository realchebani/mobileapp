import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_fonts.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// The Realesty Material 3 theme (light only; night colors are used locally
/// by the voice and camera screens).
ThemeData realestyTheme() {
  const c = RealestyColors.light;
  final textTheme = RealestyTextStyles.textTheme.apply(
    bodyColor: c.encre,
    displayColor: c.encre,
  );
  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: c.encre,
    onPrimary: c.surface,
    primaryContainer: c.surface2,
    onPrimaryContainer: c.encre,
    secondary: c.vertTexte,
    onSecondary: c.surface,
    secondaryContainer: c.vertTeinte,
    onSecondaryContainer: c.vertTexte,
    tertiary: c.vert,
    onTertiary: c.encre,
    tertiaryContainer: c.vertTeinte,
    onTertiaryContainer: c.encre,
    error: c.erreur,
    onError: c.surface,
    errorContainer: c.erreurFond,
    onErrorContainer: c.erreur,
    surface: c.surface,
    onSurface: c.encre,
    onSurfaceVariant: c.texteDiscret,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surface2,
    outline: c.ligne,
    outlineVariant: c.bordureCarte,
    shadow: c.encre,
    scrim: c.encre,
    inverseSurface: c.encre,
    onInverseSurface: c.surface,
    inversePrimary: c.lueur,
    surfaceTint: Colors.transparent,
  );

  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(RealestyRadius.button)),
  );
  const buttonSize = Size.fromHeight(52);
  const buttonPadding = EdgeInsets.symmetric(horizontal: RealestySpacing.md);

  OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(RealestyRadius.field),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: c.ivoire,
    canvasColor: c.ivoire,
    fontFamily: RealestyFonts.hankenGrotesk,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    dividerColor: c.bordureCarte,
    splashFactory: NoSplash.splashFactory,
    extensions: const [c],
    iconTheme: IconThemeData(color: c.encre, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: c.ivoire,
      foregroundColor: c.encre,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge,
    ),
    dividerTheme: DividerThemeData(
      color: c.bordureCarte,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.encre,
        foregroundColor: c.surface,
        disabledBackgroundColor: c.encre.withValues(alpha: 0.4),
        disabledForegroundColor: c.surface,
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: RealestyTextStyles.button,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.encre,
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: buttonShape,
        side: BorderSide(color: c.ligne, width: RealestyBorders.medium),
        textStyle: RealestyTextStyles.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.vertTexte,
        minimumSize: const Size(44, 44),
        shape: buttonShape,
        textStyle: RealestyTextStyles.button,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: RealestyTextStyles.body.copyWith(color: c.placeholder),
      labelStyle: RealestyTextStyles.label.copyWith(color: c.encre2),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      errorStyle: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
      border: fieldBorder(c.ligne),
      enabledBorder: fieldBorder(c.ligne),
      disabledBorder: fieldBorder(c.ligne),
      focusedBorder: fieldBorder(c.encre, RealestyBorders.medium),
      errorBorder: fieldBorder(c.erreur, RealestyBorders.medium),
      focusedErrorBorder: fieldBorder(c.erreur, RealestyBorders.medium),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.encre,
      selectionColor: c.vertTeinte,
      selectionHandleColor: c.vertTexte,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(RealestyRadius.tag)),
      ),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected) ? c.encre : c.ligne,
          width: RealestyBorders.medium,
        ),
      ),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.encre : c.surface,
      ),
      checkColor: WidgetStatePropertyAll(c.surface),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(c.surface),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.vertTexte : c.ligne,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.encre,
      contentTextStyle: RealestyTextStyles.snackBar.copyWith(color: c.surface),
      actionTextColor: c.lueur,
      insetPadding: const EdgeInsets.all(RealestySpacing.gutter),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(RealestyRadius.field)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.vert,
      linearTrackColor: c.bordureCarte,
      circularTrackColor: c.bordureCarte,
      linearMinHeight: 6,
      borderRadius: BorderRadius.circular(RealestyRadius.pill),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.surface,
      // Approximates the level-2 shadow (0 12 40 rgba(20,26,23,.18)).
      elevation: 12,
      modalElevation: 12,
      shadowColor: c.encre.withValues(alpha: 0.18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RealestyRadius.sheet),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: c.ligne,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(RealestyRadius.sheet)),
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        side: BorderSide(color: c.bordureCarte),
      ),
    ),
  );
}
