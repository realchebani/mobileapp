import 'package:property_repository/property_repository.dart';
import 'package:property_repository/src/models/json.dart';
import 'package:test/test.dart';

void main() {
  group('encodeDbValue', () {
    test('encodes enums, dates, lists and maps', () {
      expect(
        encodeDbValue({
          'type': PropertyType.house,
          'list': [OutdoorEquipment.pool, OutdoorEquipment.gardenShed],
          'date': DateTime.utc(2026, 9, 30, 12),
          'nested': {'a': Provenance.document},
          'plain': 3,
          'none': null,
        }),
        {
          'type': 'maison',
          'list': ['piscine', 'abri_jardin'],
          'date': '2026-09-30T12:00:00.000Z',
          'nested': {'a': 'document'},
          'plain': 3,
          'none': null,
        },
      );
    });
  });

  test('encodeMonth formats the first day of the month', () {
    expect(encodeMonth(DateTime(2025, 3, 17)), '2025-03-01');
  });

  test('readers accept nulls', () {
    expect(readDouble(null), isNull);
    expect(readInt(null), isNull);
    expect(readDateTime(null), isNull);
    expect(readDouble(2), 2.0);
    expect(readInt(2.0), 2);
  });
}
