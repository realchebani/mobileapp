/// An enumeration stored as a `text` column constrained by a `check`.
abstract interface class DbEnum {
  /// The value stored in the database.
  String get value;
}

/// Parses a stored [raw] value among [values], or returns `null` when it is
/// null or unknown.
T? parseDbEnum<T extends DbEnum>(List<T> values, Object? raw) {
  for (final value in values) {
    if (value.value == raw) return value;
  }
  return null;
}

/// Parses a stored `text[]` among [values], ignoring unknown entries.
List<T> parseDbEnumList<T extends DbEnum>(List<T> values, Object? raw) => [
  for (final item in raw as List<Object?>? ?? const [])
    ?parseDbEnum(values, item),
];

/// Life cycle of a seller dossier (`properties.status`).
enum PropertyStatus implements DbEnum {
  /// Being filled in the tunnel.
  draft('draft'),

  /// Sent to the expert (V7).
  submitted('submitted'),

  /// Being reviewed by the expert.
  inReview('in_review'),

  /// Certified value available.
  certified('certified');

  new(this.value);

  @override
  final String value;
}

/// V1 · single or multiple owners.
enum OwnershipType implements DbEnum {
  single('single'),
  multiple('multiple');

  new(this.value);

  @override
  final String value;
}

/// V2 · special situations of the parcel.
enum SpecialSituation implements DbEnum {
  rightOfWay('servitude_passage'),
  networkEasement('servitude_reseaux'),
  other('autre'),
  none('aucune');

  new(this.value);

  @override
  final String value;
}

/// V3 · type of property.
enum PropertyType implements DbEnum {
  house('maison'),
  apartment('appartement'),
  land('terrain'),
  other('autre');

  new(this.value);

  @override
  final String value;
}

/// V3 · reason for the sale.
enum SaleReason implements DbEnum {
  relocation('mutation'),
  moreSpace('agrandissement'),
  separation('separation'),
  investment('investissement'),
  other('autre');

  new(this.value);

  @override
  final String value;
}

/// V4b · number of levels.
enum PropertyLevels implements DbEnum {
  singleStorey('plain_pied'),
  oneUpperFloor('r1'),
  twoOrMoreUpperFloors('r2_plus');

  new(this.value);

  @override
  final String value;
}

/// V4b · material of the walls.
enum WallMaterial implements DbEnum {
  concreteBlock('parpaing'),
  brick('brique'),
  stone('pierre'),
  concrete('beton'),
  rubble('moellon'),
  wood('bois'),
  rammedEarth('pise');

  new(this.value);

  @override
  final String value;
}

/// V4b · number of shared walls.
enum Adjacency implements DbEnum {
  detached('independant'),
  oneSide('1'),
  twoSides('2'),
  threeSides('3');

  new(this.value);

  @override
  final String value;
}

/// V4b · main heating energy (legacy `heating_energy`, superseded by
/// [HeatingSystem]; its codes are the first ones of [HeatingSystem]).
enum HeatingEnergy implements DbEnum {
  electricity('electricite'),
  gas('gaz'),
  fuelOil('fioul'),
  heatPump('pac'),
  wood('bois');

  new(this.value);

  @override
  final String value;
}

/// V4b · heating systems (multiple choice, `heating_systems`).
enum HeatingSystem implements DbEnum {
  /// Radiateurs électriques.
  electricity('electricite'),
  heatPump('pac'),
  gas('gaz'),
  fuelOil('fioul'),

  /// Chaudière ou poêle à bois.
  wood('bois'),

  /// Poêle à granulés.
  pellets('granules'),

  /// Cheminée ou insert.
  fireplace('cheminee'),
  districtHeating('reseau_chaleur'),
  solar('solaire'),
  other('autre');

  new(this.value);

  @override
  final String value;
}

/// V4b · sanitation.
enum Sanitation implements DbEnum {
  mainsSewer('tout_a_l_egout'),
  septicTank('fosse_septique'),
  soakaway('puits_perdu');

  new(this.value);

  @override
  final String value;
}

/// V4b · outdoor equipment (multiple choice).
enum OutdoorEquipment implements DbEnum {
  pool('piscine'),
  garage('garage'),
  terrace('terrasse'),
  gardenShed('abri_jardin'),
  motorizedGate('portail_motorise');

  new(this.value);

  @override
  final String value;
}

/// V5 · how rooms were measured (also the source of a `Room`).
enum MeasurementMethod implements DbEnum {
  scan('scan'),
  plan('plan'),
  manual('manual');

  new(this.value);

  @override
  final String value;
}

/// V6 · overlooking neighbours.
enum Overlooking implements DbEnum {
  none('aucun'),
  slight('leger'),
  significant('important');

  new(this.value);

  @override
  final String value;
}

/// Where an answer comes from (`properties.provenance` values).
enum Provenance implements DbEnum {
  declared('declared'),
  document('document'),
  external('external'),
  expert('expert'),
  ai('ai');

  new(this.value);

  @override
  final String value;
}

/// V5c · level of a room.
enum RoomLevel implements DbEnum {
  basement('sous_sol'),
  groundFloor('rdc'),
  firstFloor('etage_1'),
  secondFloor('etage_2'),
  attic('combles');

  new(this.value);

  @override
  final String value;
}

/// V5c · glazing of a room.
enum Glazing implements DbEnum {
  single('simple'),
  double('double'),
  triple('triple');

  new(this.value);

  @override
  final String value;
}

/// V6 · kind of lifestyle item.
enum LifestyleItemKind implements DbEnum {
  asset('asset'),
  watchPoint('watch_point');

  new(this.value);

  @override
  final String value;
}

/// V6 · how a lifestyle item was captured.
enum LifestyleItemSource implements DbEnum {
  declared('declared'),
  voice('voice');

  new(this.value);

  @override
  final String value;
}

/// V7 · kind of document.
enum DocumentKind implements DbEnum {
  titleDeed('titre_propriete'),
  propertyTax('taxe_fonciere'),
  energyBills('facture_energie'),
  worksInvoice('facture_travaux'),
  identityDocument('piece_identite'),
  diagnostics('diagnostics'),
  sanitationReport('rapport_spanc'),
  plan('plan'),
  other('autre');

  new(this.value);

  @override
  final String value;
}

/// V7 · analysis status of a document.
enum DocumentStatus implements DbEnum {
  received('received'),
  analyzing('analyzing'),
  analyzed('analyzed'),
  rejected('rejected');

  new(this.value);

  @override
  final String value;
}
