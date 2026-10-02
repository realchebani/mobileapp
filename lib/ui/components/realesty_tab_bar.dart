import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/realesty_pressable.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// An entry of [RealestyTabBar].
class RealestyTab {
  const new({required this.icon, required this.label, this.badge = false});

  final RealestyIcons icon;
  final String label;

  /// Shows an unread dot on the icon.
  final bool badge;
}

/// Bottom tab bar: white with a top card border; each tab is a 22 icon
/// over an 11 label, the active one in encre (700) with a 4×4 green dot.
class RealestyTabBar extends StatelessWidget {
  const new({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  final List<RealestyTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Accessibility label of the bar (e.g. "Navigation principale").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.bordureCarte)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: RealestySpacing.xs),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RealestySpacing.xs,
              6,
              RealestySpacing.xs,
              0,
            ),
            child: Row(
              children: [
                for (final (index, tab) in tabs.indexed)
                  Expanded(
                    child: _TabItem(
                      tab: tab,
                      selected: index == currentIndex,
                      onPressed: () => onTap(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const new({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final RealestyTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final color = selected ? c.encre : c.texteDiscret;
    return RealestyPressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: tab.label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 3,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  RealestyIcon(tab.icon, size: 22, color: color),
                  if (tab.badge)
                    Positioned(
                      right: -3,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: c.erreur,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RealestyTextStyles.tabLabel.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.vert : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
