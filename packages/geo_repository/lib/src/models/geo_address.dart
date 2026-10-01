import 'package:equatable/equatable.dart';
import 'package:geo_repository/src/models/geo_point.dart';

/// Precision of a [GeoAddress] (BAN `type`).
enum GeoAddressType {
  /// A house number ("12 rue de la Colombe").
  housenumber,

  /// A street, without number.
  street,

  /// A place name (lieu-dit).
  locality,

  /// A whole municipality.
  municipality,

  /// A type this version does not know.
  unknown;

  /// Parses a BAN `type`.
  static GeoAddressType parse(Object? raw) => values.firstWhere(
    (type) => type != unknown && type.name == raw,
    orElse: () => unknown,
  );
}

/// {@template geo_address}
/// A French address from the Base Adresse Nationale (BAN).
/// {@endtemplate}
class GeoAddress extends Equatable {
  /// {@macro geo_address}
  const new({
    required this.id,
    required this.label,
    required this.point,
    this.type = GeoAddressType.unknown,
    this.name,
    this.housenumber,
    this.street,
    this.postcode,
    this.city,
    this.citycode,
    this.banId,
  });

  /// Builds an address from a BAN GeoJSON feature (a point).
  factory fromFeature(Map<String, dynamic> feature) {
    final properties = feature['properties'] as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    return GeoAddress(
      id: properties['id'] as String,
      label: properties['label'] as String,
      point: GeoPoint.fromGeoJson(geometry['coordinates'] as List<dynamic>),
      type: GeoAddressType.parse(properties['type']),
      name: properties['name'] as String?,
      housenumber: properties['housenumber'] as String?,
      street: properties['street'] as String?,
      postcode: properties['postcode'] as String?,
      city: properties['city'] as String?,
      citycode: properties['citycode'] as String?,
      banId: properties['banId'] as String?,
    );
  }

  /// BAN interoperability key (e.g. `69043_jj2dze_00012`).
  final String id;

  /// Full address, e.g. "12 rue de la Colombe 69630 Chaponost".
  final String label;

  /// Position of the address.
  final GeoPoint point;

  final GeoAddressType type;

  /// First line, e.g. "12 rue de la Colombe".
  final String? name;
  final String? housenumber;
  final String? street;
  final String? postcode;
  final String? city;

  /// INSEE code of the municipality.
  final String? citycode;

  /// Unique BAN identifier (UUID), when the address has one.
  final String? banId;

  /// Whether the address locates a building or a street (not only a
  /// municipality or a place name).
  bool get isPrecise =>
      type == GeoAddressType.housenumber || type == GeoAddressType.street;

  @override
  List<Object?> get props => [
    id,
    label,
    point,
    type,
    name,
    housenumber,
    street,
    postcode,
    city,
    citycode,
    banId,
  ];
}
