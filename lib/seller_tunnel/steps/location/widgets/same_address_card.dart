import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// The other property of the seller whose address [property] most likely
/// shares (V2 "Même adresse que…", EPIC-13): a property of its lot first,
/// else the most recently created one with an address; null when none.
Property? sameAddressCandidate(Property property, List<Property> properties) {
  final located = [
    for (final other in properties)
      if (other.id != property.id &&
          other.addressLabel != null &&
          other.lat != null &&
          other.lng != null)
        other,
  ];
  final lot = property.lotId;
  return located
          .where((other) => lot != null && other.lotId == lot)
          .firstOrNull ??
      located.lastOrNull;
}

/// The address of [property] as an address suggestion.
GeoAddress addressOf(Property property) => GeoAddress(
  id: property.addressBanId ?? 'property:${property.id}',
  label: property.addressLabel!,
  point: GeoPoint(property.lat!, property.lng!),
  housenumber: property.addressHousenumber,
  street: property.addressStreet,
  postcode: property.addressPostcode,
  city: property.addressCity,
  citycode: property.addressCitycode,
  banId: property.addressBanId,
);

/// "Même adresse que Maison · 12 rue des Lilas ?" (V2): reuses the address
/// of another property of the seller; its parcel stays to confirm.
class SameAddressCard extends StatelessWidget {
  const new({required this.property, required this.onUse, super.key});

  /// The property whose address is suggested.
  final Property property;

  /// Picks the address (null while busy).
  final ValueChanged<GeoAddress>? onUse;

  /// The card for the dossier [current], when the seller has another
  /// property with an address (and the address is not chosen yet).
  static Widget? of(
    BuildContext context, {
    required Property current,
    required ValueChanged<GeoAddress>? onUse,
  }) {
    final properties = context.select<SellerPropertiesCubit?, List<Property>>(
      (cubit) => cubit?.state.properties ?? const [],
    );
    final candidate = sameAddressCandidate(current, properties);
    if (candidate == null) return null;
    return SameAddressCard(property: candidate, onUse: onUse);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final onUse = this.onUse;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Text(
            l10n.locationSameAsTitle(propertyShortLabel(l10n, property)),
            style: RealestyTextStyles.body.copyWith(
              color: c.encre,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            property.addressLabel!,
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          ),
          Text(
            l10n.locationSameAsNote,
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          ),
          RealestyButton(
            label: l10n.locationSameAsAction,
            variant: RealestyButtonVariant.secondary,
            leadingIcon: RealestyIcons.pin,
            height: 44,
            onPressed: onUse == null ? null : () => onUse(addressOf(property)),
          ),
        ],
      ),
    );
  }
}
