import 'package:property_repository/property_repository.dart';

// Options of the V4b selects. The design shows a single value for each;
// the lists are the spec's proposals ("Open questions"). They are stored as
// these codes in free `text` columns (≤ 30 characters).

/// V4b · Exposition (`properties.orientation`).
enum Exposure implements DbEnum {
  north('nord'),
  northEast('nord_est'),
  east('est'),
  southEast('sud_est'),
  south('sud'),
  southWest('sud_ouest'),
  west('ouest'),
  northWest('nord_ouest'),

  /// Windows on two opposite sides.
  dualAspect('traversant');

  new(this.value);

  @override
  final String value;
}

/// V4b · Toiture (`properties.roof_type`).
enum RoofType implements DbEnum {
  tiles('tuiles'),
  slate('ardoises'),
  flatRoof('toit_terrasse'),
  steelSheet('bac_acier'),
  zinc('zinc'),
  other('autre');

  new(this.value);

  @override
  final String value;
}

/// V4b · Type de PAC (`properties.heat_pump_type`).
enum HeatPumpType implements DbEnum {
  airToWater('air_eau'),
  airToAir('air_air'),
  geothermal('geothermique');

  new(this.value);

  @override
  final String value;
}

/// V4b · Type de piscine (`properties.pool_type`).
enum PoolType implements DbEnum {
  inGroundLiner('enterree_liner'),
  inGroundShell('enterree_coque'),
  inGroundConcrete('enterree_beton'),
  semiInGround('semi_enterree'),
  aboveGround('hors_sol');

  new(this.value);

  @override
  final String value;
}
