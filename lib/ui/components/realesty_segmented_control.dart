import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/components/realesty_pressable.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// A segment of a [RealestySegmentedControl].
@immutable
class RealestySegment<T> {
  const new({required this.value, required this.label, this.icon});

  final T value;
  final String label;

  /// Optional 16px icon before the label.
  final RealestyIcons? icon;
}

/// Segmented control: Surface 2 track, white elevated thumb on the
/// selected segment.
class RealestySegmentedControl<T> extends StatelessWidget {
  const new({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<RealestySegment<T>> segments;
  final T selected;

  /// Null disables the control.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      // Vertical track padding lives inside each segment so that the tap
      // area is 48 high while the visible segment stays 40.
      padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.xxs),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(RealestyRadius.button),
      ),
      child: Row(
        spacing: RealestySpacing.xxs,
        children: [
          for (final segment in segments)
            Expanded(
              child: _Segment<T>(
                segment: segment,
                isSelected: segment.value == selected,
                onPressed: onChanged == null
                    ? null
                    : () => onChanged!(segment.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const new({
    required this.segment,
    required this.isSelected,
    required this.onPressed,
  });

  final RealestySegment<T> segment;
  final bool isSelected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final foreground = isSelected ? c.encre : c.texteDiscret;
    return RealestyPressable(
      selected: isSelected,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: RealestySpacing.xxs),
        child: AnimatedContainer(
          duration: RealestyMotion.short,
          curve: RealestyMotion.shortCurve,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? c.surface : c.surface.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(RealestyRadius.segment),
            boxShadow: isSelected ? RealestyShadows.level1 : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              if (segment.icon != null)
                RealestyIcon(segment.icon!, size: 16, color: foreground),
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RealestyTextStyles.segment.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
