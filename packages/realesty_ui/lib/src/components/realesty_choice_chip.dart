import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/components/realesty_pressable.dart';
import 'package:realesty_ui/src/icons/realesty_icon.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// Pill choice chip (height 40 in a 44 touch target). Selected chips get a
/// green tint, a green border and a leading check.
class RealestyChoiceChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;

  /// Called with the toggled value; null disables the chip.
  final ValueChanged<bool>? onSelected;

  /// 16px icon shown when unselected (selected chips show a check).
  final RealestyIcons? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final glyph = selected ? RealestyIcons.check : icon;
    return RealestyPressable(
      selected: selected,
      onPressed: onSelected == null ? null : () => onSelected!(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: AnimatedContainer(
          duration: RealestyMotion.short,
          curve: RealestyMotion.shortCurve,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? c.vertTeinte : c.surface,
            borderRadius: BorderRadius.circular(RealestyRadius.pill),
            border: Border.all(
              color: selected ? c.vertTexte : c.ligne,
              width: RealestyBorders.medium,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (glyph != null)
                RealestyIcon(
                  glyph,
                  size: 16,
                  color: selected ? c.vertTexte : c.encre,
                ),
              Text(
                label,
                style:
                    (selected
                            ? RealestyTextStyles.segment
                            : RealestyTextStyles.chip)
                        .copyWith(color: c.encre),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
