import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/realesty_pressable.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Counter row: title (and subtitle) with − value + buttons, clamped to
/// [min]…[max].
class RealestyStepper extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.min = 0,
    this.max,
    this.decrementLabel = 'Diminuer',
    this.incrementLabel = 'Augmenter',
    super.key,
  }) : assert(max == null || max >= min, 'max must be >= min');

  final String title;
  final String? subtitle;
  final int value;

  /// Called with the new value; null disables both buttons.
  final ValueChanged<int>? onChanged;

  final int min;

  /// Upper bound, unbounded when null.
  final int? max;

  /// Accessibility labels of the buttons (suffixed with [title]).
  final String decrementLabel;
  final String incrementLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final canDecrement = onChanged != null && value > min;
    final canIncrement = onChanged != null && (max == null || value < max!);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: RealestySpacing.minTouchTarget,
      ),
      child: Row(
        spacing: RealestySpacing.sm,
        children: [
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
          _StepButton(
            icon: RealestyIcons.minus,
            semanticLabel: '$decrementLabel $title',
            onPressed: canDecrement ? () => onChanged!(value - 1) : null,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 20),
            child: Semantics(
              liveRegion: true,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: RealestyTextStyles.stepperValue.copyWith(color: c.encre),
              ),
            ),
          ),
          _StepButton(
            icon: RealestyIcons.plus,
            semanticLabel: '$incrementLabel $title',
            onPressed: canIncrement ? () => onChanged!(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final RealestyIcons icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    // 40px visual circle centered in a 44px touch target; the 12px row gap
    // plus the 2px inset gives the specified 14px visual gap.
    return RealestyPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: SizedBox.square(
        dimension: RealestySpacing.minTouchTarget,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface,
              border: Border.all(color: c.ligne, width: RealestyBorders.medium),
            ),
            child: RealestyIcon(icon, size: 18, color: c.encre),
          ),
        ),
      ),
    );
  }
}
