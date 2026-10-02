import 'package:intl/intl.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Maison" / "Appartement" / "Garage ou dépendance" (the estimated
/// types; garages and outbuildings share the DVF « Dépendance » sales).
String marketTypeLabel(AppLocalizations l10n, PropertyType? type) =>
    switch (type) {
      PropertyType.apartment => l10n.marketTypeApartment,
      PropertyType.outbuilding ||
      PropertyType.parking => l10n.marketTypeOutbuilding,
      _ => l10n.marketTypeHouse,
    };

/// Whether [type] is priced per unit (garages and outbuildings: no
/// surface, no price per m²).
bool isPricedPerUnit(PropertyType? type) =>
    type == PropertyType.outbuilding || type == PropertyType.parking;

/// "350 m", "1,2 km".
String marketDistance(AppLocalizations l10n, int meters) => meters < 1000
    ? l10n.marketDistanceM(frenchNumber(meters))
    : l10n
          .marketDistanceKm(frenchNumber(meters / 1000, decimalDigits: 1))
          .replaceFirst(',0$noBreakSpace', noBreakSpace);

/// "décembre 2025" in the app language.
String marketLongMonth(AppLocalizations l10n, DateTime month) =>
    DateFormat.yMMMM(l10n.localeName).format(month);

/// "+2,1 %", "−0,4 %".
String marketSignedPercent(AppLocalizations l10n, double value) {
  final number = frenchNumber(value.abs(), decimalDigits: 1);
  final sign = value > 0
      ? '+'
      : value < 0
      ? '−'
      : '';
  return l10n.marketPercent('$sign$number');
}
