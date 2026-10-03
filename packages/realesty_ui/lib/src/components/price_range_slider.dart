import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// A price slider around a certified range (V11a): the track spans 85 % of
/// [low] to 115 % of [high] in steps of [step]; the [low]–[high] band is
/// tinted; labels of both bounds and a centred [caption] underneath.
class PriceRangeSlider extends StatelessWidget {
  const new({
    required this.low,
    required this.high,
    required this.value,
    required this.onChanged,
    required this.lowLabel,
    required this.highLabel,
    required this.caption,
    required this.semanticLabel,
    this.step = 1000,
    super.key,
  });

  final int low;
  final int high;
  final int value;
  final ValueChanged<int>? onChanged;
  final String lowLabel;
  final String highLabel;
  final String caption;
  final String semanticLabel;
  final int step;

  /// Lowest value of the track.
  int get min => (low * 0.85 / step).floor() * step;

  /// Highest value of the track.
  int get max => (high * 1.15 / step).ceil() * step;

  /// Whether [value] is within the certified range.
  bool get inRange => value >= low && value <= high;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final min = this.min;
    final max = this.max;
    final clamped = value.clamp(min, max);
    final style = RealestyTextStyles.caption.copyWith(color: c.texteDiscret);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: RealestySpacing.minTouchTarget,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                left: 24,
                right: 24,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final from = (low - min) / (max - min) * width;
                    final to = (high - min) / (max - min) * width;
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned(
                          left: from,
                          width: to - from,
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: c.vertTeinte,
                              borderRadius: BorderRadius.circular(
                                RealestyRadius.pill,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: c.vertTexte,
                  inactiveTrackColor: c.ligne,
                  thumbColor: c.encre,
                  overlayColor: c.vertTexte.withValues(alpha: 0.12),
                ),
                child: Slider(
                  value: clamped.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: ((max - min) / step).round(),
                  semanticFormatterCallback: (_) => semanticLabel,
                  onChanged: onChanged == null
                      ? null
                      : (value) => onChanged!(value.round()),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.xs),
          child: Row(
            children: [
              Text(lowLabel, style: style),
              Expanded(
                child: Text(caption, textAlign: TextAlign.center, style: style),
              ),
              Text(highLabel, style: style),
            ],
          ),
        ),
      ],
    );
  }
}
