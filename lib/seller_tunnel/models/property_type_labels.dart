import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Name of [type], as on its V3 card ("Maison", "Garage / parking"…).
String propertyTypeName(AppLocalizations l10n, PropertyType type) =>
    switch (type) {
      PropertyType.house => l10n.contextTypeHouse,
      PropertyType.apartment => l10n.contextTypeApartment,
      PropertyType.land => l10n.contextTypeLand,
      PropertyType.parking => l10n.contextTypeParking,
      PropertyType.outbuilding => l10n.contextTypeOutbuilding,
      PropertyType.commercial => l10n.contextTypeCommercial,
      PropertyType.building => l10n.contextTypeBuilding,
      PropertyType.other => l10n.contextTypeOther,
    };

/// Short label of the type of [property]: the seller's precision for an
/// outbuilding or "Autre" when given ("Grange"), else the type name; null
/// while the type is not chosen.
String? propertyTypeLabel(AppLocalizations l10n, Property property) {
  final type = property.propertyType;
  if (type == null) return null;
  final other = property.propertyTypeOther?.trim() ?? '';
  final precise =
      (type == PropertyType.other || type == PropertyType.outbuilding) &&
      other.isNotEmpty;
  return precise ? other : propertyTypeName(l10n, type);
}

/// Icon of [type] (V3 cards, "Mes biens").
RealestyIcons propertyTypeIcon(PropertyType? type) => switch (type) {
  PropertyType.house => RealestyIcons.home,
  PropertyType.apartment => RealestyIcons.building,
  PropertyType.land => RealestyIcons.land,
  PropertyType.parking => RealestyIcons.garage,
  PropertyType.outbuilding => RealestyIcons.cube,
  PropertyType.commercial => RealestyIcons.store,
  PropertyType.building => RealestyIcons.buildings,
  PropertyType.other || null => RealestyIcons.grid,
};

/// Subtitle of the V3 card of [type] (examples), if any.
String? propertyTypeSubtitle(AppLocalizations l10n, PropertyType type) =>
    switch (type) {
      PropertyType.house || PropertyType.apartment || PropertyType.land => null,
      PropertyType.parking => l10n.contextTypeParkingSubtitle,
      PropertyType.outbuilding => l10n.contextTypeOutbuildingSubtitle,
      PropertyType.commercial => l10n.contextTypeCommercialSubtitle,
      PropertyType.building => l10n.contextTypeBuildingSubtitle,
      PropertyType.other => l10n.contextTypeOtherSubtitle,
    };

/// "Maison · 12 rue des Lilas": the type and the street (or the city) of
/// [property], to tell the seller's properties apart.
String propertyShortLabel(AppLocalizations l10n, Property property) {
  final type = propertyTypeLabel(l10n, property) ?? l10n.myPropertiesUntitled;
  final street = [
    property.addressHousenumber,
    property.addressStreet,
  ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
  final where = street.isNotEmpty ? street : property.addressCity ?? '';
  return where.trim().isEmpty ? type : '$type · $where';
}

/// Status of [property] in "Mes biens": "Brouillon · étape 3/7",
/// "Envoyé", "Analyse en cours", "Certifié".
String propertyStatusLabel(AppLocalizations l10n, Property property) {
  switch (property.status) {
    case PropertyStatus.draft:
      final profile = PropertyTypeProfile.of(property.propertyType);
      return l10n.myPropertiesStatusDraft(
        profile.positionOf(profile.resumeAt(property.currentStep)),
        profile.stepCount,
      );
    case PropertyStatus.submitted:
      return l10n.myPropertiesStatusSubmitted;
    case PropertyStatus.inReview:
      return l10n.myPropertiesStatusInReview;
    case PropertyStatus.certified:
      return l10n.myPropertiesStatusCertified;
  }
}
