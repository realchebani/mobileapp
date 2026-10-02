import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/report/widgets/report_blocks.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// V9b · "Synthèse": key figures, how the value was reached, why, the
/// price / delay curve, the expert's word and the next step.
class SynthesisTab extends StatelessWidget {
  const new({required this.valuation, required this.onSell, super.key});

  final Valuation valuation;

  /// "Mettre en vente à …" (formula choice).
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final weeks = valuation.estimatedDelayWeeks;
    final quote = valuation.expertQuote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Expanded(
                child: ReportStatTile(
                  label: l10n.reportAdvisedPrice,
                  value: euros(l10n, valuation.valueEur),
                  hint: l10n.reportAdvisedPriceHint,
                  highlighted: true,
                ),
              ),
              if (weeks != null)
                Expanded(
                  child: ReportStatTile(
                    label: l10n.reportDelay,
                    value: l10n.reportDelayValue(weeks),
                    hint: l10n.reportDelayHint,
                  ),
                ),
            ],
          ),
        ),
        if (valuation.methodSteps.isNotEmpty)
          ReportCard(
            title: l10n.reportHowTitle,
            children: [
              for (final (index, step) in valuation.methodSteps.indexed)
                _MethodStep(
                  number: index + 1,
                  step: step,
                  last: index == valuation.methodSteps.length - 1,
                ),
            ],
          ),
        if (valuation.reasons.isNotEmpty)
          ReportCard(
            title: l10n.reportWhyTitle,
            children: [
              for (final reason in valuation.reasons) _Reason(reason: reason),
            ],
          ),
        if (valuation.delayCurve.isNotEmpty)
          ReportCard(
            title: l10n.reportDelayTitle,
            subtitle: l10n.reportDelaySubtitle,
            children: [
              for (final (index, point) in valuation.delayCurve.indexed)
                _DelayPoint(
                  point: point,
                  tone: _tone(valuation.delayCurve, index, valuation.valueEur),
                ),
            ],
          ),
        if (quote != null)
          _ExpertQuote(
            quote: quote,
            name: valuation.expertDisplayName,
            initials: valuation.expertInitials,
          ),
        ReportCard(
          title: l10n.reportNextTitle,
          children: [
            ActionCard(
              icon: RealestyIcons.trending,
              title: l10n.reportSellTitle(frenchNumber(valuation.valueEur)),
              subtitle: l10n.reportSellSubtitle,
              variant: ActionCardVariant.accent,
              onPressed: onSell,
            ),
          ],
        ),
      ],
    );
  }

  /// Below the value: good; the value: highlighted; the first price above:
  /// warning; further: bad.
  static _DelayTone _tone(
    List<ValuationDelayPoint> curve,
    int index,
    int value,
  ) {
    final price = curve[index].priceEur;
    if (price < value) return _DelayTone.good;
    if (price == value) return _DelayTone.advised;
    final above = curve.where((point) => point.priceEur > value).toList();
    return above.indexOf(curve[index]) == 0
        ? _DelayTone.warning
        : _DelayTone.bad;
  }
}

class _MethodStep extends StatelessWidget {
  const new({required this.number, required this.step, required this.last});

  final int number;
  final ValuationMethodStep step;

  /// The final value: dark row.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final detail = step.detail;
    final foreground = last ? c.nuitTexte : c.encre;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: last ? c.encre : c.surface2,
          borderRadius: BorderRadius.circular(RealestyRadius.field),
        ),
        child: Row(
          spacing: RealestySpacing.sm,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: last ? c.vert : c.surface,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: RealestyTextStyles.badge.copyWith(color: c.encre),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: RealestyTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        fontSize: 12,
                        color: last ? c.nuitTexteDiscret : c.texteDiscret,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              step.isDelta
                  ? signedEuros(l10n, step.amountEur)
                  : euros(l10n, step.amountEur),
              style: RealestyTextStyles.stepperValue.copyWith(
                fontSize: 16,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const new({required this.reason});

  final ValuationReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final style = RealestyTextStyles.bodySmall.copyWith(height: 1.45);
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Semantics(
            label: reason.positive ? l10n.reportPositive : l10n.reportNegative,
            excludeSemantics: true,
            child: SizedBox(
              width: 12,
              child: Text(
                reason.positive ? '+' : '−',
                style: style.copyWith(
                  fontWeight: FontWeight.w700,
                  color: reason.positive ? c.vertTexte : c.attention,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(reason.text, style: style.copyWith(color: c.encre2)),
          ),
        ],
      ),
    );
  }
}

enum _DelayTone { good, advised, warning, bad }

class _DelayPoint extends StatelessWidget {
  const new({required this.point, required this.tone});

  final ValuationDelayPoint point;
  final _DelayTone tone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final color = switch (tone) {
      _DelayTone.good => c.vertTexte,
      _DelayTone.advised => c.vertTexte,
      _DelayTone.warning => c.attention,
      _DelayTone.bad => c.erreur,
    };
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: tone == _DelayTone.advised ? c.vertTeinte : c.surface2,
          borderRadius: BorderRadius.circular(RealestyRadius.field),
        ),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tone == _DelayTone.good ? c.vert : color,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Text(
                euros(l10n, point.priceEur),
                style: RealestyTextStyles.stepperValue.copyWith(
                  fontSize: 15,
                  color: c.encre,
                ),
              ),
            ),
            Flexible(
              child: Text(
                point.label,
                textAlign: TextAlign.right,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpertQuote extends StatelessWidget {
  const new({required this.quote, required this.name, this.initials});

  final String quote;
  final String name;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return SellerSpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(
            '«$noBreakSpace$quote$noBreakSpace»',
            style: RealestyTextStyles.bodySmall.copyWith(
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: c.encre2,
            ),
          ),
          Row(
            spacing: 10,
            children: [
              InitialsAvatar(initials ?? InitialsAvatar.of(name), size: 32),
              Expanded(
                child: Text(
                  context.l10n.reportExpertSignature(name),
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
