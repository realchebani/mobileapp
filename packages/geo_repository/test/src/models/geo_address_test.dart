import 'package:geo_repository/geo_repository.dart';
import 'package:test/test.dart';

void main() {
  group('GeoAddressType', () {
    test('parses BAN types', () {
      expect(GeoAddressType.parse('housenumber'), GeoAddressType.housenumber);
      expect(GeoAddressType.parse('street'), GeoAddressType.street);
      expect(GeoAddressType.parse('locality'), GeoAddressType.locality);
      expect(GeoAddressType.parse('municipality'), GeoAddressType.municipality);
      expect(GeoAddressType.parse('unknown'), GeoAddressType.unknown);
      expect(GeoAddressType.parse('other'), GeoAddressType.unknown);
      expect(GeoAddressType.parse(null), GeoAddressType.unknown);
    });
  });

  group('GeoAddress', () {
    test('is built from a BAN feature', () {
      final address = GeoAddress.fromFeature(const {
        'geometry': {
          'type': 'Point',
          'coordinates': [4.739579, 45.707956],
        },
        'properties': {
          'label': '12 rue de la Colombe 69630 Chaponost',
          'housenumber': '12',
          'id': '69043_jj2dze_00012',
          'banId': 'ban-uuid',
          'name': '12 rue de la Colombe',
          'postcode': '69630',
          'citycode': '69043',
          'city': 'Chaponost',
          'type': 'housenumber',
          'street': 'rue de la Colombe',
        },
      });
      expect(
        address,
        const GeoAddress(
          id: '69043_jj2dze_00012',
          label: '12 rue de la Colombe 69630 Chaponost',
          point: GeoPoint(45.707956, 4.739579),
          type: GeoAddressType.housenumber,
          name: '12 rue de la Colombe',
          housenumber: '12',
          street: 'rue de la Colombe',
          postcode: '69630',
          city: 'Chaponost',
          citycode: '69043',
          banId: 'ban-uuid',
        ),
      );
    });

    test('is precise for a house number or a street', () {
      GeoAddress withType(GeoAddressType type) => GeoAddress(
        id: 'id',
        label: 'label',
        point: const GeoPoint(0, 0),
        type: type,
      );
      expect(withType(GeoAddressType.housenumber).isPrecise, isTrue);
      expect(withType(GeoAddressType.street).isPrecise, isTrue);
      expect(withType(GeoAddressType.locality).isPrecise, isFalse);
      expect(withType(GeoAddressType.municipality).isPrecise, isFalse);
      expect(withType(GeoAddressType.unknown).isPrecise, isFalse);
    });
  });
}
