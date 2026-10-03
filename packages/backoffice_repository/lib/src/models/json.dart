/// JSON object as returned by the `bo_*` functions.
typedef JsonMap = Map<String, dynamic>;

/// Readers tolerant to the JSON shapes PostgREST returns.
abstract final class Json {
  static int? integer(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static double? number(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static DateTime? date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String? text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static JsonMap? map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static List<JsonMap> maps(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item),
  ];

  static List<T> list<T>(Object? value, T Function(JsonMap) read) => [
    for (final item in maps(value)) read(item),
  ];
}
