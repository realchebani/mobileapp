import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/realesty_pressable.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Visual variants of [RealestyButton].
enum RealestyButtonVariant {
  /// Encre background, white text — the main action.
  primary,

  /// Vert Realesty background, encre text.
  accent,

  /// White background, Ligne border, encre text.
  secondary,

  /// Transparent, Vert texte label.
  text,
}

/// Full-width Realesty button (height 52, radius 14, 1.5 border).
class RealestyButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.variant = RealestyButtonVariant.primary,
    this.leadingIcon,
    this.isLoading = false,
    this.loadingSemanticLabel = 'chargement en cours',
    this.height = 52,
    this.expand = true,
    super.key,
  });

  final String label;

  /// Tap callback; null disables the button (opacity 0.4).
  final VoidCallback? onPressed;

  final RealestyButtonVariant variant;

  /// Optional 20px icon before the label.
  final RealestyIcons? leadingIcon;

  /// Replaces the label with a spinner and blocks taps. Screen readers
  /// announce "[label], [loadingSemanticLabel]".
  final bool isLoading;

  /// Suffix announced while [isLoading] (French default).
  final String loadingSemanticLabel;

  /// 52 by default, 56 for onboarding CTAs.
  final double height;

  /// Whether the button takes the full available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
    final (
      Color background,
      Color foreground,
      Color border,
    ) = switch (variant) {
      RealestyButtonVariant.primary => (
        colors.encre,
        colors.surface,
        colors.encre,
      ),
      RealestyButtonVariant.accent => (colors.vert, colors.encre, colors.vert),
      RealestyButtonVariant.secondary => (
        colors.surface,
        colors.encre,
        colors.ligne,
      ),
      RealestyButtonVariant.text => (
        Colors.transparent,
        colors.vertTexte,
        Colors.transparent,
      ),
    };

    final Widget content = isLoading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
              backgroundColor: Colors.transparent,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: RealestySpacing.xs,
            children: [
              if (leadingIcon != null)
                RealestyIcon(leadingIcon!, color: foreground),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: RealestyTextStyles.button.copyWith(color: foreground),
                ),
              ),
            ],
          );

    return RealestyPressable(
      onPressed: isLoading ? null : onPressed,
      showDisabled: !isLoading,
      semanticLabel: isLoading ? '$label, $loadingSemanticLabel' : label,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(RealestyRadius.button),
          border: Border.all(color: border, width: RealestyBorders.medium),
        ),
        child: content,
      ),
    );
  }
}
