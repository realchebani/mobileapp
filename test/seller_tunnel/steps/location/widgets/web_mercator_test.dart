import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/web_mercator.dart';

void main() {
  group('WebMercator', () {
    test('projects to the standard tile pyramid', () {
      final offset = WebMercator.project(
        const GeoPoint(45.707956, 4.739579),
        19,
      );
      // Tile of the point checked against the IGN WMTS.
      expect((offset / WebMercator.tileSize).dx.floor(), 269046);
      expect((offset / WebMercator.tileSize).dy.floor(), 187132);
      expect(WebMercator.worldSize(0), 256);
    });

    test('unprojects back to the point', () {
      const point = GeoPoint(45.707956, 4.739579);
      final back = WebMercator.unproject(WebMercator.project(point, 18), 18);
      expect(back.lat, closeTo(point.lat, 1e-9));
      expect(back.lng, closeTo(point.lng, 1e-9));
    });

    test('boundsCenter is the middle of the bounding box', () {
      expect(WebMercator.boundsCenter(const []), isNull);
      expect(
        WebMercator.boundsCenter(const [
          GeoPoint(1, 2),
          GeoPoint(3, 10),
          GeoPoint(2, 4),
        ]),
        const GeoPoint(2, 6),
      );
    });

    test('fitZoom picks the highest zoom showing all points', () {
      const viewport = Size(350, 210);
      const a = GeoPoint(45.7080, 4.7395);
      const b = GeoPoint(45.7078, 4.7398);
      expect(
        WebMercator.fitZoom(const [a, b], viewport, minZoom: 14, maxZoom: 19),
        19,
      );
      expect(
        WebMercator.fitZoom(
          const [a, GeoPoint(45.71, 4.745)],
          viewport,
          minZoom: 14,
          maxZoom: 19,
        ),
        15,
      );
      expect(
        WebMercator.fitZoom(
          const [a, GeoPoint(48.85, 2.35)],
          viewport,
          minZoom: 10,
          maxZoom: 19,
        ),
        10,
      );
      expect(
        WebMercator.fitZoom(const [], viewport, minZoom: 14, maxZoom: 18),
        18,
      );
    });
  });
}
