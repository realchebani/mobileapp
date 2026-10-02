import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

export 'package:mobileapp/seller_tunnel/models/property_type_labels.dart'
    show propertyTypeLabel;

/// "525 000 €".
String euros(AppLocalizations l10n, int amount) =>
    l10n.reportEuros(frenchNumber(amount));

/// "+ 4 000 €" / "− 5 000 €".
String signedEuros(AppLocalizations l10n, int amount) => amount < 0
    ? l10n.reportMinusEuros(frenchNumber(-amount))
    : l10n.reportPlusEuros(frenchNumber(amount));

/// "115 m²" (one decimal when needed).
String squareMeters(AppLocalizations l10n, double area) => l10n.reportArea(
  frenchNumber(area, decimalDigits: area == area.roundToDouble() ? 0 : 1),
);

/// "25 septembre 2026" in the app locale.
String longDate(BuildContext context, DateTime date) => withRenderableSpaces(
  DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag())
      .format(date.toLocal()),
);

/// "12 rue de la Colombe, Chaponost" (or the geocoded label).
String? propertyAddress(Property property) {
  final street = [
    property.addressHousenumber,
    property.addressStreet,
  ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
  final city = property.addressCity;
  if (street.isEmpty) return property.addressLabel;
  return city == null || city.isEmpty ? street : '$street, $city';
}
