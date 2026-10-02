import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/realesty_pressable.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Visual variants of [ActionCard].
enum ActionCardVariant {
  /// Vert Realesty background — the next action.
  accent,

  /// White card with a border.
  neutral,
}

/// Tappable row card (dashboard actions): 44 icon tile, title 16/700,
/// subtitle 13 and a chevron.
class ActionCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.variant = ActionCardVariant.neutral,
    super.key,
  });

  final RealestyIcons icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;
  final ActionCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final accent = variant == ActionCardVariant.accent;
    final subtitle = this.subtitle;
    return RealestyPressable(
      onPressed: onPressed,
      semanticLabel: subtitle == null ? title : '$title. $subtitle',
      child: Container(
        padding: const EdgeInsets.all(RealestySpacing.md),
        decoration: BoxDecoration(
          color: accent ? c.vert : c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.bubble),
          border: accent ? null : Border.all(color: c.bordureCarte),
        ),
        child: Row(
          spacing: 14,
          children: [
            Container(
              width: RealestySpacing.minTouchTarget,
              height: RealestySpacing.minTouchTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent
                    ? c.surface.withValues(alpha: 0.45)
                    : c.vertTeinte,
                borderRadius: BorderRadius.circular(RealestyRadius.field),
              ),
              child: RealestyIcon(icon, color: accent ? c.encre : c.vertTexte),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: RealestyTextStyles.body.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.encre,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: accent ? c.encre : c.texteDiscret,
                      ),
                    ),
                ],
              ),
            ),
            RealestyIcon(RealestyIcons.chevronRight, color: c.encre),
          ],
        ),
      ),
    );
  }
}
