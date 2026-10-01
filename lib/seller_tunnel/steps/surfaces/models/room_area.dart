import 'package:mobileapp/ui/format/realesty_format.dart';

/// Surfaces of V5c: parsing what is typed and formatting the French way.
abstract final class RoomArea {
  /// Accepted range of a room surface (m²).
  static const double min = 0.5;
  static const double max = 500;

  /// Maximum number of decimals (the column is `numeric(6, 2)`).
  static const int maxDecimals = 2;

  /// The surface typed in [text] ("12,5", "12.5"), or null when it is not
  /// a number.
  static double? parse(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(normalized)) return null;
    return double.parse(normalized);
  }

  /// [value] rounded to the stored precision (2 decimals).
  static double round(double value) => (value * 100).round() / 100;

  /// [value] with one decimal ("38,5", "6,0"), or two when needed
  /// ("12,25").
  static String format(double value) {
    final rounded = round(value);
    final hundredths = (rounded * 100).round();
    return frenchNumber(rounded, decimalDigits: hundredths % 10 == 0 ? 1 : 2);
  }

  /// [value] as typed in the room form ("12,5", "12").
  static String input(double value) {
    final rounded = round(value);
    final hundredths = (rounded * 100).round();
    final decimals = hundredths % 100 == 0
        ? 0
        : hundredths % 10 == 0
        ? 1
        : 2;
    return rounded.toStringAsFixed(decimals).replaceAll('.', ',');
  }

  /// [value] without decimals when it is whole ("115"), with the needed
  /// ones otherwise ("115,5"), as in the agent message.
  static String short(double value) {
    final rounded = round(value);
    final hundredths = (rounded * 100).round();
    if (hundredths % 100 == 0) return frenchNumber(rounded);
    return format(rounded);
  }
}
