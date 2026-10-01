import 'package:equatable/equatable.dart';
import 'package:geo_repository/src/models/geo_point.dart';

/// {@template cadastre_parcel}
/// A cadastral parcel from API Carto (IGN, cadastre module).
/// {@endtemplate}
class CadastreParcel extends Equatable {
  /// {@macro cadastre_parcel}
  const new({
    required this.idu,
    this.section,
    this.numero,
    this.codeInsee,
    this.communeName,
    this.areaM2,
    this.geometry,
  });

  /// Builds a parcel from an API Carto GeoJSON feature.
  factory fromFeature(Map<String, dynamic> feature) {
    final properties = feature['properties'] as Map<String, dynamic>;
    return CadastreParcel(
      idu: properties['idu'] as String,
      section: properties['section'] as String?,
      numero: properties['numero'] as String?,
      codeInsee: properties['code_insee'] as String?,
      communeName: properties['nom_com'] as String?,
      areaM2: (properties['contenance'] as num?)?.round(),
      geometry: feature['geometry'] as Map<String, dynamic>?,
    );
  }

  /// 14-character national identifier (e.g. `69043000AM0076`).
  final String idu;

  /// Cadastral section (e.g. `AM`).
  final String? section;

  /// Parcel number as registered, zero-padded (e.g. `0076`).
  final String? numero;

  /// INSEE code of the municipality.
  final String? codeInsee;

  /// Name of the municipality.
  final String? communeName;

  /// Contenance: registered area (m²).
  final int? areaM2;

  /// GeoJSON geometry (MultiPolygon, WGS 84).
  final Map<String, dynamic>? geometry;

  /// [numero] without its leading zeros (e.g. `76`), as usually written.
  String? get shortNumero {
    final value = numero;
    if (value == null) return null;
    final trimmed = value.replaceFirst(RegExp('^0+'), '');
    return trimmed.isEmpty ? value : trimmed;
  }

  /// Outer rings of the polygons of [geometry] (holes are ignored), for
  /// drawing the parcel; empty when there is no (valid) geometry.
  List<List<GeoPoint>> get outlines {
    try {
      final coordinates = geometry?['coordinates'] as List<dynamic>?;
      final polygons = switch (geometry?['type']) {
        'MultiPolygon' => coordinates!,
        'Polygon' => [coordinates],
        _ => const <Object?>[],
      };
      return [
        for (final polygon in polygons.cast<List<dynamic>>())
          if (polygon.isNotEmpty)
            [
              for (final position in (polygon.first as List<dynamic>))
                GeoPoint.fromGeoJson(position as List<dynamic>),
            ],
      ];
    } on Object {
      return const [];
    }
  }

  /// Whether [point] lies inside one of the [outlines] (ray casting;
  /// holes are ignored).
  bool contains(GeoPoint point) {
    for (final ring in outlines) {
      var inside = false;
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final a = ring[i];
        final b = ring[j];
        if ((a.lat > point.lat) != (b.lat > point.lat) &&
            point.lng <
                (b.lng - a.lng) * (point.lat - a.lat) / (b.lat - a.lat) +
                    a.lng) {
          inside = !inside;
        }
      }
      if (inside) return true;
    }
    return false;
  }

  @override
  List<Object?> get props => [
    idu,
    section,
    numero,
    codeInsee,
    communeName,
    areaM2,
    geometry,
  ];
}
