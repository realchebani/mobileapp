import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V9 · the property: photo placeholder, "Maison · 115 m² · 5 pièces",
/// address and the dossier status badge.
class PropertySummaryCard extends StatelessWidget {
  const new({required this.property, super.key});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final area = property.livingAreaM2;
    final rooms = property.roomsCount;
    final title = [
      ?propertyTypeLabel(l10n, property),
      if (area != null) squareMeters(l10n, area),
      if (rooms != null) l10n.dashboardRooms(rooms),
    ].join(' · ');
    final address = propertyAddress(property);
    final certified = property.status == PropertyStatus.certified;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Row(
        spacing: RealestySpacing.sm,
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.imagePlaceholder,
              borderRadius: BorderRadius.circular(RealestyRadius.field),
            ),
            child: RealestyIcon(RealestyIcons.home, size: 28, color: c.encre2),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: RealestySpacing.xxs,
              children: [
                Text(
                  title.isEmpty ? l10n.dashboardTitleFallback : title,
                  style: RealestyTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.encre,
                  ),
                ),
                if (address != null)
                  Text(
                    address,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                RealestyBadge(
                  label: certified
                      ? l10n.dashboardBadgeCertified
                      : l10n.dashboardBadgeInProgress,
                  variant: certified
                      ? RealestyBadgeVariant.certified
                      : RealestyBadgeVariant.neutral,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
