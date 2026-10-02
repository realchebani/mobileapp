import 'package:property_repository/property_repository.dart';
import 'package:test/test.dart';

void main() {
  group(PropertyLot, () {
    final row = <String, dynamic>{
      'id': 'lot-1',
      'owner_id': 'u1',
      'name': 'Maison + terrain',
      'sale_mode': 'ensemble_ou_separe',
      'main_property_id': 'p1',
      'created_at': '2026-10-02T10:00:00.000Z',
      'updated_at': '2026-10-02T11:00:00.000Z',
    };

    test('parses a row and writes it back', () {
      final lot = PropertyLot.fromJson(row);
      expect(lot.name, 'Maison + terrain');
      expect(lot.saleMode, LotSaleMode.togetherOrSeparately);
      expect(lot.mainPropertyId, 'p1');
      expect(lot.createdAt, DateTime.utc(2026, 10, 2, 10));
      expect(lot.toJson(), row);
    });

    test('defaults the sale mode', () {
      final lot = PropertyLot.fromJson(const {'id': 'l', 'owner_id': 'u'});
      expect(lot.saleMode, LotSaleMode.together);
      expect(lot, const PropertyLot(id: 'l', ownerId: 'u'));
    });
  });
}
