import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/realesty_pressable.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Tone of a [RealestyListItem] leading tile.
enum RealestyListTileTone {
  /// Surface 2 tile, encre icon.
  neutral,

  /// Vert teinte tile, vert texte icon.
  success,

  /// Erreur fond tile, erreur icon.
  error,
}

/// List row (min height 56): optional 40px icon tile, title/subtitle and a
/// trailing widget (usually a `RealestyBadge`); bottom divider unless last.
class RealestyListItem extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.tone = RealestyListTileTone.neutral,
    this.trailing,
    this.showDivider = true,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final RealestyIcons? leadingIcon;
  final RealestyListTileTone tone;
  final Widget? trailing;

  /// Set to false on the last item.
  final bool showDivider;

  /// Makes the row tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final (Color tileBackground, Color tileForeground) = switch (tone) {
      RealestyListTileTone.neutral => (c.surface2, c.encre),
      RealestyListTileTone.success => (c.vertTeinte, c.vertTexte),
      RealestyListTileTone.error => (c.erreurFond, c.erreur),
    };
    final row = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: RealestySpacing.sm),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: c.bordureCarte))
            : null,
      ),
      child: Row(
        spacing: RealestySpacing.sm,
        children: [
          if (leadingIcon != null)
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tileBackground,
                borderRadius: BorderRadius.circular(RealestyRadius.field),
              ),
              child: RealestyIcon(leadingIcon!, color: tileForeground),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return RealestyPressable(onPressed: onTap, child: row);
  }
}
