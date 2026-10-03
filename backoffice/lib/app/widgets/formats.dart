import 'package:realesty_ui/realesty_ui.dart';

String _two(int value) => value.toString().padLeft(2, '0');

/// 03/10/2026 (local time).
String dateFr(DateTime date) {
  final d = date.toLocal();
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// 03/10/2026 14:05 (local time).
String dateTimeFr(DateTime date) {
  final d = date.toLocal();
  return '${dateFr(d)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// 525 000 € (no-break spaces).
String euros(num value) => '${frenchNumber(value)}$noBreakSpace€';

/// 115 m², 32,5 m².
String squareMeters(num value) =>
    '${frenchNumber(value, decimalDigits: value == value.truncate() ? 0 : 1)}'
    '${noBreakSpace}m²';
