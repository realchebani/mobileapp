import 'package:intl/intl.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Maison" / "Appartement" (other types are never estimated).
String marketTypeLabel(AppLocalizations l10n, PropertyType? type) =>
    type == PropertyType.apartment
    ? l10n.marketTypeApartment
    : l10n.marketTypeHouse;

/// "350 m", "1,2 km".
String marketDistance(AppLocalizations l10n, int meters) => meters < 1000
    ? l10n.marketDistanceM(frenchNumber(meters))
    : l10n
          .marketDistanceKm(frenchNumber(meters / 1000, decimalDigits: 1))
          .replaceFirst(',0$noBreakSpace', noBreakSpace);

/// "avr. 2025" in the app language.
String marketMonth(AppLocalizations l10n, DateTime month) =>
    DateFormat.yMMM(l10n.localeName).format(month);

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
