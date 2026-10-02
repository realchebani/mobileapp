import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/lot/models/lot_estimate.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Name of [lot] for the seller: its name, else "Lot de N biens".
String lotName(AppLocalizations l10n, PropertyLot lot, int membersCount) {
  final name = lot.name?.trim() ?? '';
  return name.isNotEmpty ? name : l10n.lotDefaultName(membersCount);
}

/// "Vendus ensemble" / "Ensemble ou séparément".
String lotSaleModeLabel(AppLocalizations l10n, LotSaleMode mode) =>
    switch (mode) {
      LotSaleMode.together => l10n.lotSaleModeTogether,
      LotSaleMode.togetherOrSeparately => l10n.lotSaleModeTogetherOrSeparately,
    };

/// A sale lot ("Mes biens", home of a property of the lot): name, number of
/// properties, sale mode and, once complete, the lot estimate; opens the
/// lot.
class LotCard extends StatelessWidget {
  const new({
    required this.lot,
    required this.members,
    required this.onPressed,
    this.estimate,
    this.title,
    super.key,
  });

  final PropertyLot lot;
  final List<Property> members;
  final LotEstimate? estimate;

  /// Overrides the title (e.g. "Fait partie du lot …").
  final String? title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final estimate = this.estimate;
    final subtitle = [
      l10n.myPropertiesSummary(members.length),
      lotSaleModeLabel(l10n, lot.saleMode),
      if (estimate != null && estimate.isComplete)
        (estimate.isPartial ? l10n.lotEstimatePartial : l10n.lotEstimate)(
          euros(l10n, estimate.low!),
          euros(l10n, estimate.high!),
        ),
    ].join(' · ');
    return ActionCard(
      icon: RealestyIcons.grid,
      title: title ?? lotName(l10n, lot, members.length),
      subtitle: subtitle,
      onPressed: onPressed,
    );
  }
}
