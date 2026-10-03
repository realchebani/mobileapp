import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// Label on the left, value on the right (report and summary tables):
/// 14 Texte discret / 14/600, with a bottom border.
class KeyValueRow extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.divider = true,
    this.valueColor,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;

  /// Total line: label in encre, both 700.
  final bool emphasized;

  /// Bottom border (off for the last row).
  final bool divider;
  final Color? valueColor;

  /// Shown after the value (e.g. a provenance tag).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final trailing = this.trailing;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: c.bordureCarte))
              : null,
        ),
        // The value hugs the right edge and takes at most 60 % of the row.
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: RealestyTextStyles.bodySmall.copyWith(
                    fontSize: 14,
                    color: emphasized ? c.encre : c.texteDiscret,
                    fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.6,
                ),
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: RealestyTextStyles.bodySmall.copyWith(
                    fontSize: 14,
                    color: valueColor ?? c.encre,
                    fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
