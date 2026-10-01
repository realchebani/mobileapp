import 'package:equatable/equatable.dart';

/// {@template geo_point}
/// A WGS 84 position (degrees).
/// {@endtemplate}
class GeoPoint extends Equatable {
  /// {@macro geo_point}
  const new(this.lat, this.lng);

  /// Builds a point from GeoJSON `[longitude, latitude]` coordinates.
  factory fromGeoJson(List<dynamic> coordinates) => GeoPoint(
    (coordinates[1] as num).toDouble(),
    (coordinates[0] as num).toDouble(),
  );

  /// Latitude.
  final double lat;

  /// Longitude.
  final double lng;

  /// GeoJSON `[longitude, latitude]` coordinates.
  List<double> toGeoJson() => [lng, lat];

  @override
  List<Object?> get props => [lat, lng];

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}
