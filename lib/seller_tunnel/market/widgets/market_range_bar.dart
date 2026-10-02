import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// V8b · band of the sector's price per m² (first quartile → third
/// quartile, tick at the median) with a house marker at the property's
/// own price per m².
class MarketRangeBar extends StatelessWidget {
  const new({
    required this.low,
    required this.median,
    required this.high,
    required this.own,
    required this.semanticLabel,
    super.key,
  });

  final int low;
  final int median;
  final int high;
  final int own;
  final String semanticLabel;

  static const double _height = 44;
  static const double _marker = 32;

  /// Share (0–1) of the track of [value].
  @visibleForTesting
  static double position(int value, int low, int high, int own) {
    final min = math.min(low, own);
    final max = math.max(high, own);
    // Margin so that the band sits in the middle and the marker stays in.
    final margin = math.max((high - low) * 0.45, 1);
    final start = min - margin;
    final end = max + margin;
    return ((value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    double at(int value) => position(value, low, high, own);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final markerLeft = (width * at(own) - _marker / 2)
                .clamp(0.0, math.max(0.0, width - _marker))
                .toDouble();
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 17,
                  height: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.bordureCarte,
                      borderRadius: BorderRadius.circular(RealestyRadius.pill),
                    ),
                  ),
                ),
                Positioned(
                  left: width * at(low),
                  width: width * (at(high) - at(low)),
                  top: 17,
                  height: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.vertTeinte,
                      border: Border.all(color: c.vertTexte),
                      borderRadius: BorderRadius.circular(RealestyRadius.pill),
                    ),
                  ),
                ),
                Positioned(
                  left: width * at(median) - 1,
                  top: 12,
                  width: 2,
                  height: 20,
                  child: ColoredBox(color: c.texteDiscret),
                ),
                Positioned(
                  left: markerLeft,
                  top: 6,
                  child: Container(
                    width: _marker,
                    height: _marker,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.encre,
                    ),
                    child: RealestyIcon(
                      RealestyIcons.home,
                      size: 16,
                      color: c.surface,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
