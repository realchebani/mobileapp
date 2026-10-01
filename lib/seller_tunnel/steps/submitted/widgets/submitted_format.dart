import 'package:mobileapp/l10n/l10n.dart';

String _two(int value) => value.toString().padLeft(2, '0');

/// "24/09" (local time).
String dayMonth(DateTime date) {
  final local = date.toLocal();
  return '${_two(local.day)}/${_two(local.month)}';
}

/// "24/09/2026" (local time).
String fullDate(DateTime date) => '${dayMonth(date)}/${date.toLocal().year}';

/// "18 h 42" (local time).
String timeOfDay(AppLocalizations l10n, DateTime date) {
  final local = date.toLocal();
  return l10n.submittedTime(local.hour.toString(), _two(local.minute));
}
