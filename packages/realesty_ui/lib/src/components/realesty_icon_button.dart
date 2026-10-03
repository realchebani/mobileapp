import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/components/realesty_pressable.dart';
import 'package:realesty_ui/src/icons/realesty_icon.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';

/// 44×44 circular icon button (white with a card border, or dark on night
/// screens).
class RealestyIconButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.dark = false,
    super.key,
  });

  final RealestyIcons icon;

  /// Accessibility label (e.g. "Retour", "Fermer").
  final String semanticLabel;

  final VoidCallback? onPressed;

  /// Nuit 2 background with a white icon.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
    return RealestyPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: Container(
        width: RealestySpacing.minTouchTarget,
        height: RealestySpacing.minTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? colors.nuit2 : colors.surface,
          border: dark ? null : Border.all(color: colors.bordureCarte),
        ),
        child: RealestyIcon(
          icon,
          color: dark ? colors.nuitTexte : colors.encre,
        ),
      ),
    );
  }
}

/// 56px green microphone button with its tinted ring (voice input).
class RealestyMicButton extends StatelessWidget {
  const new({
    required this.onPressed,
    this.semanticLabel = 'Parler à l’agent',
    super.key,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
    return RealestyPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.vert,
          boxShadow: [BoxShadow(color: colors.vertTeinte, spreadRadius: 6)],
        ),
        child: RealestyIcon(RealestyIcons.mic, size: 24, color: colors.encre),
      ),
    );
  }
}
