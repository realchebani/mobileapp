import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// Single-choice card (spec 0.4, V1 and V3): icon tile and radio dot on
/// top, title and optional subtitle below. Lay several out with
/// [SelectableCardGrid].
class SelectableCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final RealestyIcons icon;
  final String title;
  final String? subtitle;
  final bool selected;

  /// Tap callback; null disables the card.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return RealestyPressable(
      onPressed: onTap,
      selected: selected,
      child: AnimatedContainer(
        duration: RealestyMotion.short,
        curve: RealestyMotion.shortCurve,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? c.vertTeinte : c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.card),
          border: Border.all(
            color: selected ? c.vertTexte : c.ligne,
            width: RealestyBorders.medium,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: RealestySpacing.sm,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? c.surface : c.surface2,
                    borderRadius: BorderRadius.circular(RealestyRadius.field),
                  ),
                  child: RealestyIcon(
                    icon,
                    color: selected ? c.vertTexte : c.encre,
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? c.vertTexte : c.surface,
                    border: Border.all(
                      color: selected ? c.vertTexte : c.ligne,
                      width: RealestyBorders.medium,
                    ),
                  ),
                  child: selected
                      ? RealestyIcon(
                          RealestyIcons.check,
                          size: 14,
                          color: c.surface,
                        )
                      : null,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: RealestyTextStyles.listTitle.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: c.encre,
                  ),
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
          ],
        ),
      ),
    );
  }
}

/// Two-column grid of [SelectableCard]s; cards of a row share its height.
class SelectableCardGrid extends StatelessWidget {
  const new({
    required this.children,
    this.spacing = RealestySpacing.sm,
    super.key,
  });

  final List<Widget> children;

  /// Gap between cards (12; 10 on V3).
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: [
        for (var i = 0; i < children.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: spacing,
              children: [
                Expanded(child: children[i]),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
