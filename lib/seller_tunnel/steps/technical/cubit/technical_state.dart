part of 'technical_cubit.dart';

/// Why a V4b answer is not accepted.
enum TechnicalError {
  /// A required answer is missing.
  required,

  /// The year is outside its accepted range (see the `…MinYear` getters).
  yearRange,

  /// The area is not between [TechnicalState.minLivingArea] (or
  /// [TechnicalState.minLivingRoomArea]) and [TechnicalState.maxArea].
  areaRange,

  /// The living room is larger than the living area.
  livingRoomTooLarge,

  /// The pool dimensions are not "length × width".
  dimensions,
}

/// Answers of V4b · Audit technique, as edited.
final class TechnicalState extends Equatable {
  const new({
    required this.property,
    required this.today,
    this.constructionYear = '',
    this.exposure,
    this.livingArea = '',
    this.livingRoomArea = '',
    this.rooms = minRooms,
    this.bedrooms = 0,
    this.levels,
    this.wallMaterial,
    this.adjacency,
    this.roofType,
    this.roofYear = '',
    this.heatingEnergy,
    this.heatPumpType,
    this.heatPumpYear = '',
    this.sanitation,
    this.outdoorEquipment = const [],
    this.poolType,
    this.poolDimensions = '',
    this.showErrors = false,
    this.submitAttempts = 0,
    this.saveRequests = 0,
  });

  /// Answers saved in the dossier.
  factory fromProperty(Property property, DateTime today) {
    final length = property.poolLengthM;
    final width = property.poolWidthM;
    return TechnicalState(
      property: property,
      today: today,
      constructionYear: property.constructionYear?.toString() ?? '',
      exposure: parseDbEnum(Exposure.values, property.orientation),
      livingArea: formatDecimal(property.livingAreaM2),
      livingRoomArea: formatDecimal(property.livingRoomAreaM2),
      rooms: (property.roomsCount ?? minRooms).clamp(minRooms, maxRooms),
      bedrooms: (property.bedroomsCount ?? 0).clamp(
        0,
        (property.roomsCount ?? minRooms).clamp(minRooms, maxRooms),
      ),
      levels: property.levels,
      wallMaterial: property.wallMaterial,
      adjacency: property.adjacency,
      roofType: parseDbEnum(RoofType.values, property.roofType),
      roofYear: property.roofYear?.toString() ?? '',
      heatingEnergy: property.heatingEnergy,
      heatPumpType: parseDbEnum(HeatPumpType.values, property.heatPumpType),
      heatPumpYear: property.heatPumpYear?.toString() ?? '',
      sanitation: property.sanitation,
      outdoorEquipment: property.outdoorEquipment,
      poolType: parseDbEnum(PoolType.values, property.poolType),
      poolDimensions: length == null || width == null
          ? ''
          : '${formatDecimal(length)} × ${formatDecimal(width)}',
    );
  }

  /// Accepted construction years: [minConstructionYear] to this year.
  static const minConstructionYear = 1600;

  /// Earliest heat pump year (database bound).
  static const minHeatPumpYear = 1900;

  /// Accepted areas (m²).
  static const minLivingArea = 5;
  static const minLivingRoomArea = 1;
  static const maxArea = 2000;

  /// Accepted number of rooms.
  static const minRooms = 1;
  static const maxRooms = 30;

  /// Largest pool length or width (m), `numeric(5, 2)`.
  static const maxPoolSide = 999.99;

  /// The dossier, for its property type and the provenance of the answers.
  final Property property;

  /// Reference date for the "not in the future" checks.
  final DateTime today;

  /// Year as typed.
  final String constructionYear;
  final Exposure? exposure;

  /// Areas as typed ("38,5").
  final String livingArea;
  final String livingRoomArea;

  final int rooms;
  final int bedrooms;
  final PropertyLevels? levels;
  final WallMaterial? wallMaterial;
  final Adjacency? adjacency;
  final RoofType? roofType;
  final String roofYear;
  final HeatingEnergy? heatingEnergy;
  final HeatPumpType? heatPumpType;
  final String heatPumpYear;
  final Sanitation? sanitation;
  final List<OutdoorEquipment> outdoorEquipment;
  final PoolType? poolType;

  /// "length × width" as typed ("8 × 4").
  final String poolDimensions;

  /// Whether errors are shown (after a first "Enregistrer et continuer").
  final bool showErrors;

  /// Incremented on each rejected submission (to reveal the first error).
  final int submitAttempts;

  /// Incremented on each accepted submission (the view then saves [patch]).
  final int saveRequests;

  PropertyType? get propertyType => property.propertyType;

  /// A plot of land has no building: only sanitation and outdoor
  /// equipment are asked.
  bool get asksBuilding => propertyType != PropertyType.land;

  /// Levels, adjacency and roof belong to a whole building, not to an
  /// apartment (nor to land).
  bool get asksWholeBuilding =>
      asksBuilding && propertyType != PropertyType.apartment;

  /// "Niveaux" is required for a house only (spec).
  bool get requiresLevels => propertyType == PropertyType.house;

  bool get asksHeatPump =>
      asksBuilding && heatingEnergy == HeatingEnergy.heatPump;

  bool get asksPool => outdoorEquipment.contains(OutdoorEquipment.pool);

  /// Earliest roof year: the construction year when valid.
  int get roofMinYear {
    final built = parseYear(constructionYear);
    return constructionYearError == null && built != null
        ? built
        : minConstructionYear;
  }

  TechnicalError? get constructionYearError => asksBuilding
      ? _yearError(constructionYear, minConstructionYear, required: true)
      : null;

  TechnicalError? get livingAreaError => asksBuilding
      ? _areaError(livingArea, minLivingArea, required: true)
      : null;

  TechnicalError? get livingRoomAreaError {
    if (!asksBuilding) return null;
    final error = _areaError(livingRoomArea, minLivingRoomArea);
    final area = parseDecimal(livingRoomArea);
    if (error != null || area == null) return error;
    final living = parseDecimal(livingArea);
    if (livingAreaError == null && living != null && area > living) {
      return TechnicalError.livingRoomTooLarge;
    }
    return null;
  }

  TechnicalError? get levelsError =>
      requiresLevels && levels == null ? TechnicalError.required : null;

  TechnicalError? get roofYearError =>
      asksWholeBuilding ? _yearError(roofYear, roofMinYear) : null;

  TechnicalError? get heatingEnergyError =>
      asksBuilding && heatingEnergy == null ? TechnicalError.required : null;

  TechnicalError? get heatPumpYearError =>
      asksHeatPump ? _yearError(heatPumpYear, minHeatPumpYear) : null;

  TechnicalError? get poolDimensionsError {
    if (!asksPool || poolDimensions.trim().isEmpty) return null;
    return parseDimensions(poolDimensions) == null
        ? TechnicalError.dimensions
        : null;
  }

  /// Error of a typed year: [TechnicalError.required] when empty and
  /// [required], [TechnicalError.yearRange] when it is not a year between
  /// [min] and this year.
  TechnicalError? _yearError(String text, int min, {bool required = false}) {
    if (text.trim().isEmpty) return required ? TechnicalError.required : null;
    final year = parseYear(text);
    return year == null || year < min || year > today.year
        ? TechnicalError.yearRange
        : null;
  }

  /// Error of a typed area: [TechnicalError.required] when empty and
  /// [required], [TechnicalError.areaRange] when it is not an area between
  /// [min] and [maxArea].
  TechnicalError? _areaError(String text, int min, {bool required = false}) {
    if (text.trim().isEmpty) return required ? TechnicalError.required : null;
    final area = parseDecimal(text);
    return area == null || area < min || area > maxArea
        ? TechnicalError.areaRange
        : null;
  }

  bool get isValid =>
      constructionYearError == null &&
      livingAreaError == null &&
      livingRoomAreaError == null &&
      levelsError == null &&
      roofYearError == null &&
      heatingEnergyError == null &&
      heatPumpYearError == null &&
      poolDimensionsError == null;

  /// The `properties` columns of this step (questions not asked for this
  /// type of property are cleared).
  Map<String, Object?> get values {
    final building = asksBuilding;
    final whole = asksWholeBuilding;
    final heatPump = asksHeatPump;
    final pool = asksPool;
    final dimensions = pool ? parseDimensions(poolDimensions) : null;
    return {
      PropertyColumns.constructionYear: building
          ? parseYear(constructionYear)
          : null,
      PropertyColumns.orientation: building ? exposure : null,
      PropertyColumns.livingAreaM2: building ? parseDecimal(livingArea) : null,
      PropertyColumns.livingRoomAreaM2: building
          ? parseDecimal(livingRoomArea)
          : null,
      PropertyColumns.roomsCount: building ? rooms : null,
      PropertyColumns.bedroomsCount: building ? bedrooms : null,
      PropertyColumns.levels: whole ? levels : null,
      PropertyColumns.wallMaterial: building ? wallMaterial : null,
      PropertyColumns.adjacency: whole ? adjacency : null,
      PropertyColumns.roofType: whole ? roofType : null,
      PropertyColumns.roofYear: whole ? parseYear(roofYear) : null,
      PropertyColumns.heatingEnergy: building ? heatingEnergy : null,
      PropertyColumns.heatPumpType: heatPump ? heatPumpType : null,
      PropertyColumns.heatPumpYear: heatPump ? parseYear(heatPumpYear) : null,
      PropertyColumns.sanitation: sanitation,
      PropertyColumns.outdoorEquipment: outdoorEquipment,
      PropertyColumns.poolType: pool ? poolType : null,
      PropertyColumns.poolLengthM: dimensions?.$1,
      PropertyColumns.poolWidthM: dimensions?.$2,
    };
  }

  /// Whether the answer of [column] differs from the saved one.
  bool isChanged(String column) =>
      !_sameValue(_encode(values[column]), property.toJson()[column]);

  /// Provenance of the answer of [column]: "Déclaré" once edited, the
  /// saved provenance otherwise.
  Provenance provenanceOf(String column) =>
      isChanged(column) ? Provenance.declared : property.provenanceOf(column);

  /// [values] with the provenance of the edited answers set to "Déclaré"
  /// (other provenances are kept; cleared answers have none to record).
  Map<String, Object?> get patch {
    final values = this.values;
    final changed = [
      for (final MapEntry(:key, :value) in values.entries)
        if (value != null && isChanged(key)) key,
    ];
    return {
      ...values,
      if (changed.isNotEmpty)
        PropertyColumns.provenance: property.mergeProvenance({
          for (final column in changed) column: Provenance.declared,
        }),
    };
  }

  /// [value] as stored: enums as their code, lists item by item.
  static Object? _encode(Object? value) => switch (value) {
    DbEnum() => value.value,
    List<Object?>() => [for (final item in value) _encode(item)],
    _ => value,
  };

  static bool _sameValue(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  /// A typed four-digit year, or null.
  static int? parseYear(String text) =>
      RegExp(r'^\d{4}$').hasMatch(text.trim()) ? int.parse(text.trim()) : null;

  static final _decimal = RegExp(r'^(\d+([.,]\d{0,2})?|[.,]\d{1,2})$');

  /// A typed decimal ("38,5", also "38," or ",5"), or null.
  static double? parseDecimal(String text) {
    final compact = text.replaceAll(RegExp(r'\s'), '');
    if (!_decimal.hasMatch(compact)) return null;
    final number = compact.replaceAll(',', '.');
    return double.parse('0$number${number.endsWith('.') ? '0' : ''}');
  }

  static final _dimensions = RegExp(
    r'^(\d+(?:[.,]\d{1,2})?)[x×X*](\d+(?:[.,]\d{1,2})?)$',
  );

  /// The (length, width) of a typed "8 × 4", or null when it is not two
  /// sides between 0 and [maxPoolSide] m.
  static (double, double)? parseDimensions(String text) {
    final match = _dimensions.firstMatch(text.replaceAll(RegExp(r'\s'), ''));
    if (match == null) return null;
    final length = double.parse(match[1]!.replaceAll(',', '.'));
    final width = double.parse(match[2]!.replaceAll(',', '.'));
    bool valid(double side) => side > 0 && side <= maxPoolSide;
    return valid(length) && valid(width) ? (length, width) : null;
  }

  /// [value] as typed in the form ("38,5"), empty when null.
  static String formatDecimal(double? value) {
    if (value == null) return '';
    final fixed = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return fixed.replaceAll('.', ',');
  }

  TechnicalState copyWith({
    String? constructionYear,
    Exposure? Function()? exposure,
    String? livingArea,
    String? livingRoomArea,
    int? rooms,
    int? bedrooms,
    PropertyLevels? levels,
    WallMaterial? Function()? wallMaterial,
    Adjacency? Function()? adjacency,
    RoofType? Function()? roofType,
    String? roofYear,
    HeatingEnergy? heatingEnergy,
    HeatPumpType? Function()? heatPumpType,
    String? heatPumpYear,
    Sanitation? Function()? sanitation,
    List<OutdoorEquipment>? outdoorEquipment,
    PoolType? Function()? poolType,
    String? poolDimensions,
    bool? showErrors,
    int? submitAttempts,
    int? saveRequests,
  }) {
    return TechnicalState(
      property: property,
      today: today,
      constructionYear: constructionYear ?? this.constructionYear,
      exposure: exposure == null ? this.exposure : exposure(),
      livingArea: livingArea ?? this.livingArea,
      livingRoomArea: livingRoomArea ?? this.livingRoomArea,
      rooms: rooms ?? this.rooms,
      bedrooms: bedrooms ?? this.bedrooms,
      levels: levels ?? this.levels,
      wallMaterial: wallMaterial == null ? this.wallMaterial : wallMaterial(),
      adjacency: adjacency == null ? this.adjacency : adjacency(),
      roofType: roofType == null ? this.roofType : roofType(),
      roofYear: roofYear ?? this.roofYear,
      heatingEnergy: heatingEnergy ?? this.heatingEnergy,
      heatPumpType: heatPumpType == null ? this.heatPumpType : heatPumpType(),
      heatPumpYear: heatPumpYear ?? this.heatPumpYear,
      sanitation: sanitation == null ? this.sanitation : sanitation(),
      outdoorEquipment: outdoorEquipment ?? this.outdoorEquipment,
      poolType: poolType == null ? this.poolType : poolType(),
      poolDimensions: poolDimensions ?? this.poolDimensions,
      showErrors: showErrors ?? this.showErrors,
      submitAttempts: submitAttempts ?? this.submitAttempts,
      saveRequests: saveRequests ?? this.saveRequests,
    );
  }

  @override
  List<Object?> get props => [
    property,
    today,
    constructionYear,
    exposure,
    livingArea,
    livingRoomArea,
    rooms,
    bedrooms,
    levels,
    wallMaterial,
    adjacency,
    roofType,
    roofYear,
    heatingEnergy,
    heatPumpType,
    heatPumpYear,
    sanitation,
    outdoorEquipment,
    poolType,
    poolDimensions,
    showErrors,
    submitAttempts,
    saveRequests,
  ];
}
