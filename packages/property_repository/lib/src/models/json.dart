import 'package:property_repository/src/models/enums.dart';

/// Reads a nullable JSON number as a double (Postgres `numeric`).
double? readDouble(Object? value) => (value as num?)?.toDouble();

/// Reads a nullable JSON number as an int.
int? readInt(Object? value) => (value as num?)?.toInt();

/// Reads a nullable ISO 8601 timestamp.
DateTime? readDateTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// Encodes a value for a Supabase row: [DbEnum]s as their stored value,
/// dates as ISO 8601 strings (UTC), lists and maps recursively.
Object? encodeDbValue(Object? value) => switch (value) {
  DbEnum() => value.value,
  DateTime() => value.toUtc().toIso8601String(),
  Iterable<Object?>() => [for (final item in value) encodeDbValue(item)],
  Map<String, Object?>() => {
    for (final MapEntry(:key, value: item) in value.entries)
      key: encodeDbValue(item),
  },
  _ => value,
};

/// Formats a month as the first day of it (`yyyy-MM-01`), for `date`
/// columns holding a month.
String encodeMonth(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-'
    '${month.month.toString().padLeft(2, '0')}-01';
