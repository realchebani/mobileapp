import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/components/realesty_pressable.dart';
import 'package:realesty_ui/src/icons/realesty_icon.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// 22×22 checkbox with a top-aligned label. The whole row is tappable.
///
/// Use [richLabel] for labels containing links: style link spans with
/// [RealestyCheckbox.linkStyle] and give them their own recognizer (owned
/// by the caller, which must dispose it).
class RealestyCheckbox extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    this.label,
    this.richLabel,
    super.key,
  }) : assert(
         label != null || richLabel != null,
         'Provide a label or a richLabel',
       );

  final bool value;

  /// Called with the new value; null disables the checkbox.
  final ValueChanged<bool>? onChanged;

  final String? label;

  /// Rich label, e.g. text with links.
  final InlineSpan? richLabel;

  /// Style for link spans inside [richLabel].
  static TextStyle linkStyle(BuildContext context) => TextStyle(
    color: context.realestyColors.vertTexte,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
    final style = RealestyTextStyles.checkboxLabel.copyWith(
      color: colors.encre2,
    );
    return RealestyPressable(
      isButton: false,
      checked: value,
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: RealestySpacing.minTouchTarget,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            AnimatedContainer(
              duration: RealestyMotion.short,
              curve: RealestyMotion.shortCurve,
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? colors.encre : colors.surface,
                borderRadius: BorderRadius.circular(RealestyRadius.tag),
                border: Border.all(
                  color: value ? colors.encre : colors.ligne,
                  width: RealestyBorders.medium,
                ),
              ),
              child: value
                  ? RealestyIcon(
                      RealestyIcons.check,
                      size: 14,
                      color: colors.surface,
                    )
                  : null,
            ),
            Expanded(
              child: Text.rich(
                richLabel ?? TextSpan(text: label),
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
