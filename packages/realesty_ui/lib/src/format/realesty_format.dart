import 'package:intl/intl.dart';

/// Narrow no-break space (U+202F), used by French number formatting but
/// missing from the bundled fonts.
const narrowNoBreakSpace = ' ';

/// No-break space (U+00A0), present in the bundled fonts.
const noBreakSpace = ' ';

/// Replaces narrow no-break spaces with regular no-break spaces so the
/// text renders with the bundled fonts.
String withRenderableSpaces(String text) =>
    text.replaceAll(narrowNoBreakSpace, noBreakSpace);

/// Formats [value] the French way ("525 000", "1 234,5"), grouping with a
/// no-break space (U+00A0).
String frenchNumber(num value, {int decimalDigits = 0}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: 'fr',
    decimalDigits: decimalDigits,
  );
  return withRenderableSpaces(format.format(value));
}
