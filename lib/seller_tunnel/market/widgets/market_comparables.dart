import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/market/widgets/market_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// One comparable DVF sale: type, area, rooms; street (only when it has at
/// least 3 sales, else « Secteur proche »), year and distance; price and
/// price per m².
class MarketComparableRow extends StatelessWidget {
  const new({required this.sale, this.showDivider = true, super.key});

  final ComparableSale sale;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final type = marketTypeLabel(l10n, sale.propertyType);
    final area = frenchNumber(sale.areaM2);
    final rooms = sale.rooms;
    final title = rooms == null || rooms == 0
        ? l10n.marketComparableTitleNoRooms(type, area)
        : l10n.marketComparableTitle(type, area, rooms);
    final place = sale.street ?? l10n.marketComparableNearby;
    final year = sale.soldYear.toString();
    final distance = sale.distanceM;
    final subtitle = distance == null
        ? l10n.marketComparableSold(place, year)
        : l10n.marketComparableSoldAt(
            place,
            year,
            marketDistance(l10n, distance),
          );
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: RealestySpacing.sm),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: c.bordureCarte))
              : null,
        ),
        child: Row(
          spacing: RealestySpacing.sm,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(RealestyRadius.field),
              ),
              child: RealestyIcon(
                sale.propertyType == PropertyType.apartment
                    ? RealestyIcons.building
                    : RealestyIcons.home,
                color: c.encre,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    style: RealestyTextStyles.listTitle.copyWith(
                      color: c.encre,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: [
                Text(
                  l10n.marketPrice(frenchNumber(sale.priceEur)),
                  style: RealestyTextStyles.listTitle.copyWith(
                    fontFamily: RealestyFonts.sora,
                    color: c.encre,
                  ),
                ),
                Text(
                  l10n.marketPriceM2(frenchNumber(sale.priceM2Eur)),
                  style: RealestyTextStyles.badge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: c.texteDiscret,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// White card listing [sales].
class MarketComparablesCard extends StatelessWidget {
  const new({required this.sales, super.key});

  final List<ComparableSale> sales;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        children: [
          for (final (index, sale) in sales.indexed)
            MarketComparableRow(
              sale: sale,
              showDivider: index < sales.length - 1,
            ),
        ],
      ),
    );
  }
}

/// Every comparable sale of the estimate, in a sheet.
Future<void> showMarketComparablesSheet(
  BuildContext context,
  List<ComparableSale> sales,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => MarketComparablesSheet(sales: sales),
  );
}

class MarketComparablesSheet extends StatelessWidget {
  const new({required this.sales, super.key});

  final List<ComparableSale> sales;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RealestySpacing.gutter,
              RealestySpacing.md,
              RealestySpacing.sm,
              RealestySpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.marketAllSalesTitle,
                      style: RealestyTextStyles.title2.copyWith(color: c.encre),
                    ),
                  ),
                ),
                RealestyIconButton(
                  icon: RealestyIcons.close,
                  semanticLabel: l10n.tunnelClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                0,
                RealestySpacing.gutter,
                RealestySpacing.xl,
              ),
              children: [
                for (final (index, sale) in sales.indexed)
                  MarketComparableRow(
                    sale: sale,
                    showDivider: index < sales.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
