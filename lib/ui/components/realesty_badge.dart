import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_fonts.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Visual variants of [RealestyBadge], with their default icon.
enum RealestyBadgeVariant {
  /// Plan Essentiel — shield, green.
  essentiel(RealestyIcons.shield),

  /// Plan Premium — star, amber.
  premium(RealestyIcons.star),

  /// Plan Expert — briefcase, blue.
  expert(RealestyIcons.briefcase),

  /// Compatibility score — target, lueur on encre, Sora.
  compatibility(RealestyIcons.target),

  /// Pass Visite — shield, white on encre.
  passVisite(RealestyIcons.shield),

  /// Certified — check, green.
  certified(RealestyIcons.check),

  /// À compléter — warning colors, no icon.
  toComplete(null),

  /// Manquant — error colors, no icon.
  missing(null),

  /// Neutral — Surface 2, no icon.
  neutral(null);

  new(this.defaultIcon);

  final RealestyIcons? defaultIcon;
}

/// Pill badge (height 26, 12/700, 14px icon).
class RealestyBadge extends StatelessWidget {
  const new({
    required this.label,
    this.variant = RealestyBadgeVariant.neutral,
    this.icon,
    this.showIcon = true,
    super.key,
  });

  final String label;
  final RealestyBadgeVariant variant;

  /// Overrides the variant's default icon.
  final RealestyIcons? icon;

  /// Set to false to hide the icon.
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final (Color background, Color foreground) = switch (variant) {
      RealestyBadgeVariant.essentiel => (c.essentielFond, c.essentiel),
      RealestyBadgeVariant.premium => (c.premiumFond, c.premium),
      RealestyBadgeVariant.expert => (c.expertFond, c.expert),
      RealestyBadgeVariant.compatibility => (c.encre, c.lueur),
      RealestyBadgeVariant.passVisite => (c.encre, c.surface),
      RealestyBadgeVariant.certified => (c.vertTeinte, c.vertTexte),
      RealestyBadgeVariant.toComplete => (c.attentionFond, c.attention),
      RealestyBadgeVariant.missing => (c.erreurFond, c.erreur),
      RealestyBadgeVariant.neutral => (c.surface2, c.encre2),
    };
    final glyph = showIcon ? icon ?? variant.defaultIcon : null;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RealestyRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          if (glyph != null) RealestyIcon(glyph, size: 14, color: foreground),
          Text(
            label,
            maxLines: 1,
            style: RealestyTextStyles.badge.copyWith(
              color: foreground,
              fontFamily: variant == RealestyBadgeVariant.compatibility
                  ? RealestyFonts.sora
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
