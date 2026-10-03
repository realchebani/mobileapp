import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/models/heating_system_label.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Title and text of a listing.
typedef ListingText = ({String title, String description});

/// The listing generated from the dossier (plan Q10 · deterministic
/// template, no AI): only facts of the dossier, no figure that is not in
/// it (type, areas, rooms, year, equipment, heating, town); a lot
/// describes each of its properties.
ListingText listingTextOf(AppLocalizations l10n, List<Property> members) {
  final main = members.first;
  final city = main.addressCity?.trim();
  if (members.length > 1) {
    return (
      title: _limit(
        city == null || city.isEmpty
            ? l10n.listingTextLotTitle(members.length)
            : l10n.listingTextLotTitleCity(members.length, city),
        120,
      ),
      description: _limit(
        [
          l10n.listingTextLotIntro(members.length),
          for (final member in members) '• ${_summary(l10n, member)}',
        ].join('\n'),
        2000,
      ),
    );
  }
  final type = propertyTypeLabel(l10n, main) ?? l10n.listingTextProperty;
  final area = _area(main);
  final title = [
    if (area == null) type else l10n.listingTextTypeArea(type, area),
    if (city != null && city.isNotEmpty) l10n.listingTextInCity(city),
  ].join(' ');
  return (
    title: _limit(title, 120),
    description: _limit(_summary(l10n, main), 2000),
  );
}

String? _area(Property property) {
  final area = property.livingAreaM2 ?? property.usableAreaM2;
  if (area == null || area <= 0) return null;
  return frenchNumber(
    area,
    decimalDigits: area == area.roundToDouble() ? 0 : 1,
  );
}

String _summary(AppLocalizations l10n, Property property) {
  final type = propertyTypeLabel(l10n, property) ?? l10n.listingTextProperty;
  final area = _area(property);
  final rooms = property.roomsCount;
  final bedrooms = property.bedroomsCount;
  final city = property.addressCity?.trim();
  final first = [
    if (area == null) type else l10n.listingTextTypeArea(type, area),
    if (rooms != null && rooms > 0) l10n.listingTextRooms(rooms),
    if (bedrooms != null && bedrooms > 0) l10n.listingTextBedrooms(bedrooms),
  ].join(', ');
  final year = property.constructionYear;
  final outdoor = [
    for (final item in property.outdoorEquipment) _outdoor(l10n, item),
  ];
  final heating = [
    for (final system in property.heatingSystems)
      heatingSystemLabel(l10n, system).toLowerCase(),
  ];
  return [
    if (city == null || city.isEmpty)
      '$first.'
    else
      '$first ${l10n.listingTextInCity(city)}.',
    if (year != null) l10n.listingTextBuilt(year),
    if (outdoor.isNotEmpty) l10n.listingTextOutdoor(outdoor.join(', ')),
    if (heating.isNotEmpty) l10n.listingTextHeating(heating.join(', ')),
  ].join(' ');
}

String _outdoor(AppLocalizations l10n, OutdoorEquipment item) => switch (item) {
  OutdoorEquipment.pool => l10n.technicalOutdoorPool,
  OutdoorEquipment.garage => l10n.technicalOutdoorGarage,
  OutdoorEquipment.terrace => l10n.technicalOutdoorTerrace,
  OutdoorEquipment.gardenShed => l10n.technicalOutdoorGardenShed,
  OutdoorEquipment.motorizedGate => l10n.technicalOutdoorMotorizedGate,
}.toLowerCase();

String _limit(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max - 1)}…';
