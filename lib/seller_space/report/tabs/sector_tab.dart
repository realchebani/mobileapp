import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/report/widgets/report_blocks.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

// TODO(EPIC-05): add the €/m² curve and key figures of the sector from
// the market snapshot computed at submission (`market_snapshots`).

/// V9b · "Secteur": the DVF sales studied by the expert (street without
/// house number), the competing listings and the risks note.
class SectorTab extends StatelessWidget {
  const new({required this.valuation, super.key});

  final Valuation valuation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final note = valuation.comparablesNote;
    final risks = valuation.risksNote;
    if (valuation.comparables.isEmpty &&
        valuation.competitors.isEmpty &&
        risks == null) {
      return ReportParagraph(l10n.reportSectorEmpty);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        if (valuation.comparables.isNotEmpty)
          ReportCard(
            title: l10n.reportSoldTitle,
            subtitle: l10n.reportSoldSubtitle,
            children: [
              Column(
                children: [
                  for (final sale in valuation.comparables)
                    _SaleRow(sale: sale),
                ],
              ),
              if (note != null) ReportParagraph(note, small: true),
            ],
          ),
        if (valuation.competitors.isNotEmpty)
          ReportCard(
            title: l10n.reportCompetitorsTitle,
            subtitle: valuation.competitorsSummary,
            children: [
              Column(
                children: [
                  for (final (index, competitor)
                      in valuation.competitors.indexed)
                    _CompetitorRow(
                      letter: String.fromCharCode(0x41 + index % 26),
                      competitor: competitor,
                    ),
                ],
              ),
            ],
          ),
        if (risks != null)
          ReportParagraph(l10n.reportRisks(risks), small: true),
      ],
    );
  }
}

class _SaleRow extends StatelessWidget {
  const new({required this.sale});

  final ValuationComparable sale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final soldOn = sale.soldOn;
    final area = sale.areaM2;
    final land = sale.landM2;
    final priceM2 = sale.priceM2Eur;
    return ReportSaleRow(
      title: sale.street,
      subtitle: [
        if (soldOn != null)
          '${soldOn.month.toString().padLeft(2, '0')}/${soldOn.year}',
        if (area != null) squareMeters(l10n, area),
        if (land != null) l10n.reportLand(frenchNumber(land)),
        if (sale.excluded) l10n.reportExcluded,
      ].join(' · '),
      amount: euros(l10n, sale.priceEur),
      caption: priceM2 == null ? null : '${euros(l10n, priceM2)}/m²',
      struck: sale.excluded,
    );
  }
}

class _CompetitorRow extends StatelessWidget {
  const new({required this.letter, required this.competitor});

  final String letter;
  final ValuationCompetitor competitor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final price = competitor.priceEur;
    final note = competitor.note;
    final days = competitor.daysOnline;
    final details = [
      ?note,
      if (days != null) l10n.reportDaysOnline(days),
    ].join(' · ');
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.bordureCarte)),
        ),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: competitor.retained ? c.surface2 : c.bordureCarte,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                letter,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.encre,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      competitor.label,
                      if (price != null) euros(l10n, price),
                    ].join(' · '),
                    style: RealestyTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.encre,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        fontSize: 12,
                        color: c.texteDiscret,
                      ),
                    ),
                ],
              ),
            ),
            RealestyBadge(
              label: competitor.retained
                  ? l10n.reportRetained
                  : l10n.reportDismissed,
              variant: competitor.retained
                  ? RealestyBadgeVariant.certified
                  : RealestyBadgeVariant.neutral,
              showIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}
