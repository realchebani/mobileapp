import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/initials_avatar.dart';
import 'package:mobileapp/ui/components/realesty_pressable.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_fonts.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Dark card of a certified value (V9, V9b): caption + badge, the value
/// (Sora 34), details, the expert who validated it and an optional white
/// action button.
class HeroValueCard extends StatelessWidget {
  const new({
    required this.caption,
    required this.value,
    this.badgeLabel,
    this.details,
    this.expertInitials,
    this.expertLabel,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.header,
    super.key,
  });

  /// e.g. "Avis de valeur certifié" (rendered uppercase).
  final String caption;

  /// e.g. "525 000 €".
  final String value;

  /// Green badge next to the caption (e.g. "Certifié").
  final String? badgeLabel;

  /// Range and context under the value.
  final String? details;
  final String? expertInitials;

  /// e.g. "Validé par Julien M., expert immobilier · 25/09/2026".
  final String? expertLabel;
  final String? actionLabel;
  final RealestyIcons? actionIcon;
  final VoidCallback? onAction;

  /// Shown above the caption, followed by a separator (V9b property row).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final details = this.details;
    final expertLabel = this.expertLabel;
    final actionLabel = this.actionLabel;
    final header = this.header;
    final badgeLabel = this.badgeLabel;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.lg),
      decoration: BoxDecoration(
        color: c.encre,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          if (header != null) ...[
            header,
            Divider(height: 1, thickness: 1, color: c.nuitBordure),
          ],
          Row(
            spacing: RealestySpacing.xs,
            children: [
              Expanded(
                child: Text(
                  caption.toUpperCase(),
                  style: RealestyTextStyles.caption.copyWith(
                    color: c.nuitTexteDiscret,
                  ),
                ),
              ),
              if (badgeLabel != null) HeroBadge(label: badgeLabel),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: RealestyFonts.sora,
              fontSize: 34,
              height: 1.1,
              letterSpacing: -0.68,
              fontWeight: FontWeight.w600,
              color: c.nuitTexte,
            ),
          ),
          if (details != null)
            Text(
              details,
              style: RealestyTextStyles.bodySmall.copyWith(
                color: c.nuitTexteDiscret,
              ),
            ),
          if (expertLabel != null)
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.nuitBordure)),
              ),
              child: Row(
                spacing: 10,
                children: [
                  InitialsAvatar(
                    expertInitials ?? InitialsAvatar.of(expertLabel),
                    onDark: true,
                  ),
                  Expanded(
                    child: Text(
                      expertLabel,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.nuitTexteDiscret,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (actionLabel != null)
            RealestyPressable(
              onPressed: onAction,
              semanticLabel: actionLabel,
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(
                  horizontal: RealestySpacing.md,
                  vertical: RealestySpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(RealestyRadius.button),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: RealestySpacing.xs,
                  children: [
                    if (actionIcon case final icon?)
                      RealestyIcon(icon, color: c.encre),
                    Flexible(
                      child: Text(
                        actionLabel,
                        textAlign: TextAlign.center,
                        style: RealestyTextStyles.button.copyWith(
                          fontSize: 15,
                          color: c.encre,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lueur pill with a shield (e.g. "Certifié") for dark cards.
class HeroBadge extends StatelessWidget {
  const new({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.lueur,
        borderRadius: BorderRadius.circular(RealestyRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          RealestyIcon(RealestyIcons.shield, size: 14, color: c.encre),
          Text(label, style: RealestyTextStyles.badge.copyWith(color: c.encre)),
        ],
      ),
    );
  }
}
