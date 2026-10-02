import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Tendance IA" card (V8): indicative range computed by the backend, with
/// a range bar marking the median, its reliability and the link to the
/// market summary (V8b). Built from a `market_snapshots` result.
class AiEstimateCard extends StatelessWidget {
  const new({
    required this.low,
    required this.median,
    required this.high,
    this.computedAt,
    this.confidence,
    this.onSynthesis,
    super.key,
  });

  final int low;
  final int median;
  final int high;
  final DateTime? computedAt;

  /// Reliability of the estimate, hidden when unknown.
  final EstimateConfidenceLevel? confidence;

  /// Opens the market summary (V8b); the button is hidden when null.
  final VoidCallback? onSynthesis;

  /// Share of the track left empty on each side of the range.
  static const _margin = 0.18;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final computedAt = this.computedAt;
    final confidence = this.confidence;
    final onSynthesis = this.onSynthesis;
    final span = high - low;
    final medianShare = span <= 0
        ? 0.5
        : ((median - low) / span).clamp(0.0, 1.0);
    final medianPosition = _margin + medianShare * (1 - 2 * _margin);
    String thousands(int value) => frenchNumber(value / 1000);
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          Row(
            spacing: RealestySpacing.xs,
            children: [
              Expanded(
                child: Text(
                  l10n.submittedAiLabel.toUpperCase(),
                  style: RealestyTextStyles.caption.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ),
              RealestyBadge(
                label: l10n.submittedAiBadge,
                variant: RealestyBadgeVariant.toComplete,
              ),
            ],
          ),
          Text(
            l10n.submittedAiRange(frenchNumber(low), frenchNumber(high)),
            style: RealestyTextStyles.keyFigure.copyWith(
              fontSize: 24,
              color: c.encre,
            ),
          ),
          Semantics(
            label: l10n.submittedAiSemantics(
              frenchNumber(low),
              frenchNumber(high),
              frenchNumber(median),
            ),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RealestySpacing.xs,
              children: [
                SizedBox(
                  height: 36,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          _bar(c.bordureCarte, left: 0, width: width),
                          _bar(
                            c.vert,
                            left: width * _margin,
                            width: width * (1 - 2 * _margin),
                          ),
                          Positioned(
                            left: width * medianPosition - 2,
                            top: 2,
                            child: Container(
                              width: 4,
                              height: 32,
                              decoration: BoxDecoration(
                                color: c.encre,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Row(
                  spacing: RealestySpacing.xs,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.submittedAiThousands(thousands(low)),
                        style: RealestyTextStyles.listSubtitle.copyWith(
                          color: c.texteDiscret,
                        ),
                      ),
                    ),
                    Text(
                      l10n.submittedAiMedian(thousands(median)),
                      textAlign: TextAlign.center,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.encre,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l10n.submittedAiThousands(thousands(high)),
                        textAlign: TextAlign.right,
                        style: RealestyTextStyles.listSubtitle.copyWith(
                          color: c.texteDiscret,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (confidence != null)
            Text(
              switch (confidence) {
                EstimateConfidenceLevel.high => l10n.submittedAiConfidenceHigh,
                EstimateConfidenceLevel.medium =>
                  l10n.submittedAiConfidenceMedium,
                EstimateConfidenceLevel.low => l10n.submittedAiConfidenceLow,
              },
              style: RealestyTextStyles.listSubtitle.copyWith(
                fontWeight: FontWeight.w700,
                color: c.encre,
              ),
            ),
          Text(
            computedAt == null
                ? l10n.submittedAiComputedNoDate
                : l10n.submittedAiComputed(fullDate(computedAt)),
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          ),
          if (onSynthesis != null)
            // Secondary button whose label wraps with large text sizes
            // (RealestyButton keeps one line).
            RealestyPressable(
              onPressed: onSynthesis,
              semanticLabel: l10n.submittedAiSynthesis,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: RealestySpacing.md,
                  vertical: RealestySpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(RealestyRadius.button),
                  border: Border.all(
                    color: c.ligne,
                    width: RealestyBorders.medium,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: RealestySpacing.xs,
                  children: [
                    RealestyIcon(RealestyIcons.trending, color: c.encre),
                    Flexible(
                      child: Text(
                        l10n.submittedAiSynthesis,
                        textAlign: TextAlign.center,
                        style: RealestyTextStyles.button.copyWith(
                          fontSize: 15,
                          color: c.encre,
                        ),
                      ),
                    ),
                    RealestyIcon(
                      RealestyIcons.chevronRight,
                      size: 18,
                      color: c.encre,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(Color color, {required double left, required double width}) {
    return Positioned(
      left: left,
      width: width,
      top: 13,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(RealestyRadius.pill),
        ),
      ),
    );
  }
}
