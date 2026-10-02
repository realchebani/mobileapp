import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/report/widgets/report_blocks.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// V9b · "Prix": what moves the price and the method (from the expert),
/// then what the seller keeps (1 % vs 4 %) and the buyer's total cost
/// (notary fees ≈ 7.5 %), computed in the app from the certified value.
class PriceTab extends StatelessWidget {
  const new({required this.valuation, super.key});

  final Valuation valuation;

  /// Realesty success fee.
  static const realestyRate = 0.01;

  /// Fee of a traditional agency, for comparison.
  static const agencyRate = 0.04;

  /// Notary fees of an existing property, approximately.
  static const notaryRate = 0.075;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final value = valuation.valueEur;
    final withRealesty = (value * (1 - realestyRate)).round();
    final withAgency = (value * (1 - agencyRate)).round();
    final notary = ((value * notaryRate) / 100).round() * 100;
    final works = valuation.worksEstimateEur;
    final worksLabel = valuation.worksLabel;
    final sources = valuation.sources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        if (valuation.adjustments.isNotEmpty)
          ReportCard(
            title: l10n.reportAdjustTitle,
            children: [_Lines(lines: valuation.adjustments)],
          ),
        if (valuation.methodSummary.isNotEmpty)
          ReportCard(
            title: l10n.reportMethodTitle,
            subtitle: l10n.reportMethodSubtitle,
            children: [_Lines(lines: valuation.methodSummary)],
          ),
        ReportCard(
          title: l10n.reportNetTitle,
          subtitle: l10n.reportNetSubtitle,
          children: [
            Column(
              children: [
                KeyValueRow(
                  label: l10n.reportNetRealesty,
                  value: euros(l10n, withRealesty),
                ),
                KeyValueRow(
                  label: l10n.reportNetAgency,
                  value: euros(l10n, withAgency),
                ),
                KeyValueRow(
                  label: l10n.reportNetGain,
                  value: signedEuros(l10n, withRealesty - withAgency),
                  valueColor: c.vertTexte,
                  emphasized: true,
                  divider: false,
                ),
              ],
            ),
          ],
        ),
        ReportCard(
          title: l10n.reportBuyerTitle,
          children: [
            Column(
              children: [
                KeyValueRow(
                  label: l10n.reportBuyerPrice,
                  value: euros(l10n, value),
                ),
                KeyValueRow(
                  label: l10n.reportBuyerNotary,
                  value: euros(l10n, notary),
                ),
                if (works != null && works > 0)
                  KeyValueRow(
                    label: l10n.reportBuyerWorks(
                      worksLabel ?? l10n.reportBuyerWorksDefault,
                    ),
                    value: euros(l10n, works),
                  ),
                KeyValueRow(
                  label: l10n.reportBuyerTotal,
                  value: euros(l10n, value + notary + (works ?? 0)),
                  emphasized: true,
                  divider: false,
                ),
              ],
            ),
          ],
        ),
        if (sources != null)
          ReportParagraph(l10n.reportSources(sources), small: true),
        ReportParagraph(
          l10n.reportLegal(longDate(context, valuation.validUntil)),
          small: true,
        ),
      ],
    );
  }
}

/// Amount lines: the base and totals as values, the others signed.
class _Lines extends StatelessWidget {
  const new({required this.lines});

  final List<ValuationAmountLine> lines;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Column(
      children: [
        for (final (index, line) in lines.indexed)
          KeyValueRow(
            label: line.label,
            value: line.kind == ValuationLineKind.line
                ? signedEuros(l10n, line.amountEur)
                : euros(l10n, line.amountEur),
            emphasized: line.kind == ValuationLineKind.total,
            valueColor: line.kind == ValuationLineKind.control
                ? c.texteDiscret
                : null,
            divider: index < lines.length - 1,
          ),
      ],
    );
  }
}
