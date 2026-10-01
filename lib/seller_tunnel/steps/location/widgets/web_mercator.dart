import 'dart:math' as math;
import 'dart:ui';

import 'package:geo_repository/geo_repository.dart';

/// Web Mercator (EPSG:3857) projection of the standard 256 px tile
/// pyramid (the "PM" tile matrix set of the IGN WMTS).
abstract final class WebMercator {
  /// Side of a tile, in pixels.
  static const tileSize = 256.0;

  static const _maxLatitude = 85.05112878;

  /// Side of the world at [zoom], in pixels.
  static double worldSize(int zoom) => tileSize * math.pow(2, zoom);

  /// Pixel position of [point] in the world at [zoom].
  static Offset project(GeoPoint point, int zoom) {
    final size = worldSize(zoom);
    final lat = point.lat.clamp(-_maxLatitude, _maxLatitude) * math.pi / 180;
    final x = (point.lng + 180) / 360 * size;
    final y =
        (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * size;
    return Offset(x, y);
  }

  /// The point at the world pixel [offset] at [zoom].
  static GeoPoint unproject(Offset offset, int zoom) {
    final size = worldSize(zoom);
    final lng = offset.dx / size * 360 - 180;
    final n = math.pi - 2 * math.pi * offset.dy / size;
    final lat = 180 / math.pi * math.atan((math.exp(n) - math.exp(-n)) / 2);
    return GeoPoint(lat, lng);
  }

  /// Center of the bounding box of [points]; null when empty.
  static GeoPoint? boundsCenter(Iterable<GeoPoint> points) {
    if (points.isEmpty) return null;
    final lats = points.map((point) => point.lat);
    final lngs = points.map((point) => point.lng);
    return GeoPoint(
      (lats.reduce(math.min) + lats.reduce(math.max)) / 2,
      (lngs.reduce(math.min) + lngs.reduce(math.max)) / 2,
    );
  }

  /// The highest zoom in [minZoom]..[maxZoom] at which all [points] fit
  /// in [viewport] (with some margin); [maxZoom] when [points] is empty.
  static int fitZoom(
    Iterable<GeoPoint> points,
    Size viewport, {
    required int minZoom,
    required int maxZoom,
    double fill = 0.7,
  }) {
    if (points.isEmpty) return maxZoom;
    for (var zoom = maxZoom; zoom > minZoom; zoom--) {
      final projected = points.map((point) => project(point, zoom));
      final xs = projected.map((offset) => offset.dx);
      final ys = projected.map((offset) => offset.dy);
      final width = xs.reduce(math.max) - xs.reduce(math.min);
      final height = ys.reduce(math.max) - ys.reduce(math.min);
      if (width <= viewport.width * fill && height <= viewport.height * fill) {
        return zoom;
      }
    }
    return minZoom;
  }
}
