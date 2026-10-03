import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/ui/ui.dart';

/// A card whose header (icon, title, summary, trailing badge) opens or
/// folds its [children] (V18 rubrics).
class CollapsibleSection extends StatelessWidget {
  const new({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.summary,
    this.icon,
    this.trailing,
    super.key,
  });

  final String title;
  final String? summary;
  final RealestyIcons? icon;
  final Widget? trailing;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final icon = this.icon;
    final summary = this.summary;
    return SellerSpaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: RealestyPressable(
              onPressed: onToggle,
              showDisabled: false,
              child: Padding(
                padding: const EdgeInsets.all(RealestySpacing.md),
                child: Row(
                  spacing: RealestySpacing.sm,
                  children: [
                    if (icon != null)
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(
                            RealestyRadius.field,
                          ),
                        ),
                        child: RealestyIcon(icon, color: c.encre),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            title,
                            style: RealestyTextStyles.listTitle.copyWith(
                              color: c.encre,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (summary != null)
                            Text(
                              summary,
                              style: RealestyTextStyles.listSubtitle.copyWith(
                                color: c.texteDiscret,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ?trailing,
                    RealestyIcon(
                      expanded
                          ? RealestyIcons.chevronDown
                          : RealestyIcons.chevronRight,
                      size: 18,
                      color: c.texteDiscret,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded && children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.md,
                0,
                RealestySpacing.md,
                RealestySpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(height: 1, color: c.bordureCarte),
                  ...children,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
