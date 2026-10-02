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
    this.heatingSystems = const [],
    this.heatPumpType,
    this.heatPumpYear = '',
    this.sanitation,
    this.outdoorEquipment = const [],
    this.poolType,
    this.poolDimensions = '',
    this.usableArea = '',
    this.parkingLevel,
    this.parkingFeatures = const [],
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
      heatingSystems: property.heatingSystems,
      heatPumpType: parseDbEnum(HeatPumpType.values, property.heatPumpType),
      heatPumpYear: property.heatPumpYear?.toString() ?? '',
      sanitation: property.sanitation,
      outdoorEquipment: property.outdoorEquipment,
      poolType: parseDbEnum(PoolType.values, property.poolType),
      poolDimensions: length == null || width == null
          ? ''
          : '${formatDecimal(length)} × ${formatDecimal(width)}',
      usableArea: formatDecimal(property.usableAreaM2),
      parkingLevel: property.parkingLevel,
      parkingFeatures: property.parkingFeatures,
    );
  }

  /// Accepted construction years: [minConstructionYear] to this year.
  static const minConstructionYear = 1600;

  /// Earliest heat pump year (database bound).
  static const minHeatPumpYear = 1900;

  /// Accepted areas (m²).
  static const minLivingArea = 5;
  static const minLivingRoomArea = 1;
  static const minUsableArea = 1;
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

  /// Heating systems (multiple choice, kept in the design order).
  final List<HeatingSystem> heatingSystems;
  final HeatPumpType? heatPumpType;
  final String heatPumpYear;
  final Sanitation? sanitation;
  final List<OutdoorEquipment> outdoorEquipment;
  final PoolType? poolType;

  /// "length × width" as typed ("8 × 4").
  final String poolDimensions;

  /// Surface utile as typed (stationnement, dependance, local commercial).
  final String usableArea;
  final ParkingLevel? parkingLevel;

  /// Equipment of a parking space or an outbuilding (multiple choice).
  final List<ParkingFeature> parkingFeatures;

  /// Whether errors are shown (after a first "Enregistrer et continuer").
  final bool showErrors;

  /// Incremented on each rejected submission (to reveal the first error).
  final int submitAttempts;

  /// Incremented on each accepted submission (the view then saves [patch]).
  final int saveRequests;

  PropertyType? get propertyType => property.propertyType;

  /// The questions of this type of property (plan §7).
  PropertyTypeProfile get profile => PropertyTypeProfile.of(propertyType);

  /// Whether [field] is asked for this type of property.
  bool asks(TechnicalField field) => profile.technicalFields.contains(field);

  /// Whether [field] needs an answer for this type of property.
  bool requires(TechnicalField field) =>
      profile.requiredTechnicalFields.contains(field);

  /// "Niveaux" is required for a house only (spec).
  bool get requiresLevels => requires(TechnicalField.levels);

  /// At least one heating system is required for a house or an apartment
  /// (optional for "Autre", a commercial premises or a building).
  bool get requiresHeating => requires(TechnicalField.heating);

  /// The heat pump details are asked when a heat pump is among the systems.
  bool get asksHeatPump =>
      asks(TechnicalField.heating) &&
      heatingSystems.contains(HeatingSystem.heatPump);

  bool get asksPool =>
      asks(TechnicalField.outdoorEquipment) &&
      outdoorEquipment.contains(OutdoorEquipment.pool);

  /// Earliest roof year: the construction year when valid.
  int get roofMinYear {
    final built = parseYear(constructionYear);
    return constructionYearError == null && built != null
        ? built
        : minConstructionYear;
  }

  TechnicalError? get constructionYearError =>
      asks(TechnicalField.constructionYear)
      ? _yearError(
          constructionYear,
          minConstructionYear,
          required: requires(TechnicalField.constructionYear),
        )
      : null;

  TechnicalError? get livingAreaError => asks(TechnicalField.livingArea)
      ? _areaError(
          livingArea,
          minLivingArea,
          required: requires(TechnicalField.livingArea),
        )
      : null;

  TechnicalError? get usableAreaError => asks(TechnicalField.usableArea)
      ? _areaError(
          usableArea,
          minUsableArea,
          required: requires(TechnicalField.usableArea),
        )
      : null;

  TechnicalError? get livingRoomAreaError {
    if (!asks(TechnicalField.livingRoomArea)) return null;
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
      asks(TechnicalField.roof) ? _yearError(roofYear, roofMinYear) : null;

  TechnicalError? get heatingSystemsError =>
      requiresHeating && heatingSystems.isEmpty
      ? TechnicalError.required
      : null;

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
      usableAreaError == null &&
      livingRoomAreaError == null &&
      levelsError == null &&
      roofYearError == null &&
      heatingSystemsError == null &&
      heatPumpYearError == null &&
      poolDimensionsError == null;

  /// The `properties` columns of the questions of this type of property.
  /// The questions it does not ask are left as they are (hidden, cleared
  /// when the dossier is sent: the seller may change the type back); the
  /// details of a heat pump or a pool no longer selected are cleared.
  Map<String, Object?> get values {
    final heatPump = asksHeatPump;
    final pool = asksPool;
    final dimensions = pool ? parseDimensions(poolDimensions) : null;
    final choices = profile.parkingFeatureChoices;
    return {
      for (final field in profile.technicalFields)
        ...switch (field) {
          TechnicalField.constructionYear => {
            PropertyColumns.constructionYear: parseYear(constructionYear),
          },
          TechnicalField.exposure => {PropertyColumns.orientation: exposure},
          TechnicalField.livingArea => {
            PropertyColumns.livingAreaM2: parseDecimal(livingArea),
          },
          TechnicalField.livingRoomArea => {
            PropertyColumns.livingRoomAreaM2: parseDecimal(livingRoomArea),
          },
          TechnicalField.rooms => {
            PropertyColumns.roomsCount: rooms,
            PropertyColumns.bedroomsCount: bedrooms,
          },
          TechnicalField.levels => {PropertyColumns.levels: levels},
          TechnicalField.wallMaterial => {
            PropertyColumns.wallMaterial: wallMaterial,
          },
          TechnicalField.adjacency => {PropertyColumns.adjacency: adjacency},
          TechnicalField.roof => {
            PropertyColumns.roofType: roofType,
            PropertyColumns.roofYear: parseYear(roofYear),
          },
          TechnicalField.heating => {
            PropertyColumns.heatingSystems: heatingSystems,
            PropertyColumns.heatPumpType: heatPump ? heatPumpType : null,
            PropertyColumns.heatPumpYear: heatPump
                ? parseYear(heatPumpYear)
                : null,
          },
          TechnicalField.sanitation => {PropertyColumns.sanitation: sanitation},
          TechnicalField.outdoorEquipment => {
            PropertyColumns.outdoorEquipment: outdoorEquipment,
            PropertyColumns.poolType: pool ? poolType : null,
            PropertyColumns.poolLengthM: dimensions?.$1,
            PropertyColumns.poolWidthM: dimensions?.$2,
          },
          TechnicalField.usableArea => {
            PropertyColumns.usableAreaM2: parseDecimal(usableArea),
          },
          TechnicalField.parkingLevel => {
            PropertyColumns.parkingLevel: parkingLevel,
          },
          TechnicalField.parkingFeatures => {
            PropertyColumns.parkingFeatures: [
              for (final feature in parkingFeatures)
                if (choices.contains(feature)) feature,
            ],
          },
        },
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
    List<HeatingSystem>? heatingSystems,
    HeatPumpType? Function()? heatPumpType,
    String? heatPumpYear,
    Sanitation? Function()? sanitation,
    List<OutdoorEquipment>? outdoorEquipment,
    PoolType? Function()? poolType,
    String? poolDimensions,
    String? usableArea,
    ParkingLevel? Function()? parkingLevel,
    List<ParkingFeature>? parkingFeatures,
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
      heatingSystems: heatingSystems ?? this.heatingSystems,
      heatPumpType: heatPumpType == null ? this.heatPumpType : heatPumpType(),
      heatPumpYear: heatPumpYear ?? this.heatPumpYear,
      sanitation: sanitation == null ? this.sanitation : sanitation(),
      outdoorEquipment: outdoorEquipment ?? this.outdoorEquipment,
      poolType: poolType == null ? this.poolType : poolType(),
      poolDimensions: poolDimensions ?? this.poolDimensions,
      usableArea: usableArea ?? this.usableArea,
      parkingLevel: parkingLevel == null ? this.parkingLevel : parkingLevel(),
      parkingFeatures: parkingFeatures ?? this.parkingFeatures,
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
    heatingSystems,
    heatPumpType,
    heatPumpYear,
    sanitation,
    outdoorEquipment,
    poolType,
    poolDimensions,
    usableArea,
    parkingLevel,
    parkingFeatures,
    showErrors,
    submitAttempts,
    saveRequests,
  ];
}
