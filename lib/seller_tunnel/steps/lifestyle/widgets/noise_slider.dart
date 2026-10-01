import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// V6 "Bruit et circulation ressentis" slider (spec: new component, not in
/// the design system): 1–10 by steps of 1 on a green → red track, white
/// thumb ringed with the track color under it, tick labels 1…10 (the
/// selected one in Encre) and the end labels below.
///
/// While [value] is null (not answered yet) the thumb rests on
/// [restingValue] with a neutral ring and no tick is highlighted; the first
/// tap or drag sets a value.
class NoiseSlider extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    required this.semanticValue,
    required this.minLabel,
    required this.maxLabel,
    super.key,
  });

  static const int min = 1;
  static const int max = 10;

  /// Where the thumb rests while [value] is null.
  static const int restingValue = 5;

  /// Track gradient of the mockup (no design system token: specific to
  /// this slider).
  static const List<Color> trackColors = [
    Color(0xFF2E9E3F),
    Color(0xFF8CC63F),
    Color(0xFFF2C230),
    Color(0xFFF08A24),
    Color(0xFFD33A2C),
  ];
  static const List<double> trackStops = [0, 0.28, 0.52, 0.74, 1];

  static const double _inset = 14;
  static const double _thumbSize = 30;
  static const double _height = 36;

  final int? value;

  /// Null disables the slider.
  final ValueChanged<int>? onChanged;

  /// Read by assistive technologies, e.g. "Bruit et circulation ressentis".
  final String semanticLabel;

  /// The current value as announced, e.g. "3/10 · Calme".
  final String semanticValue;

  /// Left end label ("Très calme").
  final String minLabel;

  /// Right end label ("Très bruyant").
  final String maxLabel;

  /// Position (0–1) of [level] on the track.
  static double fractionOf(int level) => (level - min) / (max - min);

  /// The track color at [fraction] (0–1).
  static Color colorAt(double fraction) {
    for (var i = 1; i < trackStops.length; i++) {
      if (fraction <= trackStops[i]) {
        final t =
            (fraction - trackStops[i - 1]) /
            (trackStops[i] - trackStops[i - 1]);
        return Color.lerp(trackColors[i - 1], trackColors[i], t)!;
      }
    }
    return trackColors.last;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final current = value;
    final enabled = onChanged != null;
    final shown = current ?? restingValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Semantics(
          slider: true,
          enabled: enabled,
          label: semanticLabel,
          value: semanticValue,
          // Unanswered, either step answers the value shown.
          increasedValue: current == null
              ? '$shown/$max'
              : '${(shown + 1).clamp(min, max)}/$max',
          decreasedValue: current == null
              ? '$shown/$max'
              : '${(shown - 1).clamp(min, max)}/$max',
          onIncrease: enabled && shown < max
              ? () => onChanged!(current == null ? shown : shown + 1)
              : null,
          onDecrease: enabled && shown > min
              ? () => onChanged!(current == null ? shown : shown - 1)
              : null,
          child: ExcludeSemantics(
            child: Opacity(
              opacity: enabled ? 1 : RealestyPressable.disabledOpacity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth - 2 * _inset;
                  double xOf(int level) =>
                      _inset + fractionOf(level) * trackWidth;
                  int levelAt(double dx) {
                    final fraction = ((dx - _inset) / trackWidth).clamp(0, 1);
                    return (min + fraction * (max - min)).round();
                  }

                  void update(Offset position) {
                    final level = levelAt(position.dx);
                    if (level != current) onChanged!(level);
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: enabled ? (d) => update(d.localPosition) : null,
                    onHorizontalDragStart: enabled
                        ? (d) => update(d.localPosition)
                        : null,
                    onHorizontalDragUpdate: enabled
                        ? (d) => update(d.localPosition)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 2,
                      children: [
                        SizedBox(
                          height: _height,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _inset,
                                ),
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      RealestyRadius.pill,
                                    ),
                                    gradient: const LinearGradient(
                                      colors: trackColors,
                                      stops: trackStops,
                                    ),
                                  ),
                                ),
                              ),
                              AnimatedPositioned(
                                duration: RealestyMotion.short,
                                curve: RealestyMotion.shortCurve,
                                left: xOf(shown) - _thumbSize / 2,
                                top: (_height - _thumbSize) / 2,
                                child: Container(
                                  key: const Key('noiseSlider_thumb'),
                                  width: _thumbSize,
                                  height: _thumbSize,
                                  decoration: BoxDecoration(
                                    color: c.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: current == null
                                          ? c.ligne
                                          : colorAt(fractionOf(current)),
                                      width: 3,
                                    ),
                                    // Mockup `0 2px 8px` Encre 25 %: no token
                                    // for this one.
                                    boxShadow: [
                                      BoxShadow(
                                        color: c.encre.withValues(alpha: 0.25),
                                        offset: const Offset(0, 2),
                                        blurRadius: 7,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 16,
                          child: Stack(
                            children: [
                              for (var level = min; level <= max; level++)
                                Positioned(
                                  left: xOf(level) - 10,
                                  width: 20,
                                  child: Text(
                                    '$level',
                                    textAlign: TextAlign.center,
                                    style: RealestyTextStyles.tag.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: level == current
                                          ? c.encre
                                          : c.texteDiscret,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: RealestySpacing.sm,
          children: [
            Flexible(
              child: Text(
                minLabel,
                style: RealestyTextStyles.badge.copyWith(color: c.vertTexte),
              ),
            ),
            Flexible(
              child: Text(
                maxLabel,
                textAlign: TextAlign.end,
                style: RealestyTextStyles.badge.copyWith(color: c.erreur),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
