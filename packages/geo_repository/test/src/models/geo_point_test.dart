import 'package:geo_repository/geo_repository.dart';
import 'package:test/test.dart';

void main() {
  group('GeoPoint', () {
    test('reads and writes GeoJSON [lng, lat] coordinates', () {
      final point = GeoPoint.fromGeoJson(const [4.7, 45]);
      expect(point, const GeoPoint(45, 4.7));
      expect(point.toGeoJson(), [4.7, 45.0]);
    });

    test('has a readable toString', () {
      expect(const GeoPoint(45.5, 4.5).toString(), 'GeoPoint(45.5, 4.5)');
    });
  });
}
