import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:property_repository/property_repository.dart';

/// What V3 asks to qualify the type of property.
enum PropertyTypeDetail {
  /// Nothing more.
  none,

  /// Terrain: constructible or not (`land_kind`).
  landKind,

  /// Garage / parking: box, garage, covered or outdoor space
  /// (`parking_kind`).
  parkingKind,

  /// Free text (`property_type_other`): "grange", "péniche"…
  otherText,

  /// Local commercial: its use (`commercial_use`).
  commercialUse,

  /// Immeuble: number of dwellings (`units_count`).
  unitsCount,
}

/// A question of V4b · Audit technique.
enum TechnicalField {
  constructionYear([PropertyColumns.constructionYear]),
  exposure([PropertyColumns.orientation]),
  livingArea([PropertyColumns.livingAreaM2]),
  livingRoomArea([PropertyColumns.livingRoomAreaM2]),
  rooms([PropertyColumns.roomsCount, PropertyColumns.bedroomsCount]),
  levels([PropertyColumns.levels]),
  wallMaterial([PropertyColumns.wallMaterial]),
  adjacency([PropertyColumns.adjacency]),
  roof([PropertyColumns.roofType, PropertyColumns.roofYear]),

  /// Heating systems, and the heat pump details when there is one.
  heating([
    PropertyColumns.heatingSystems,
    PropertyColumns.heatPumpType,
    PropertyColumns.heatPumpYear,
  ]),
  sanitation([PropertyColumns.sanitation]),

  /// Outdoor equipment, and the pool details when there is one.
  outdoorEquipment([
    PropertyColumns.outdoorEquipment,
    PropertyColumns.poolType,
    PropertyColumns.poolLengthM,
    PropertyColumns.poolWidthM,
  ]),

  /// Surface utile (stationnement, dependance, local commercial).
  usableArea([PropertyColumns.usableAreaM2]),

  /// Level of a parking space.
  parkingLevel([PropertyColumns.parkingLevel]),

  /// Equipment of a parking space or an outbuilding.
  parkingFeatures([PropertyColumns.parkingFeatures]);

  new(this.columns);

  /// The `properties` columns this question writes.
  final List<String> columns;
}

/// How the seller tunnel adapts to a type of property (EPIC-13, plan
/// §7): steps, questions, documents, transparency score, voice and
/// estimate. The single place where the app decides by property type; the
/// Edge Functions follow the same table (voice and estimate: parity
/// fixture `supabase/functions/tests/fixtures/property_type_profiles.json`).
///
/// Changing the type of a draft hides the answers that no longer apply
/// without erasing them; they are cleared when the dossier is sent
/// ([clearedOnSubmit], owner decision Q9).
final class PropertyTypeProfile extends Equatable {
  const new _({
    required this.type,
    required this.steps,
    required this.voice,
    required this.estimate,
    required this.asksSelfBuilt,
    required this.detail,
    required this.technicalFields,
    required this.requiredTechnicalFields,
    this.parkingFeatureChoices = const [],
    this.asksNeighbourhood = true,
    this.roomsOptional = false,
    this.documentKinds = _dwellingDocuments,
  });

  /// The profile of [type] (all steps while the type is not chosen).
  factory of(PropertyType? type) => switch (type) {
    null => _undecided,
    PropertyType.house => _house,
    PropertyType.apartment => _apartment,
    PropertyType.land => _land,
    PropertyType.parking => _parking,
    PropertyType.outbuilding => _outbuilding,
    PropertyType.commercial => _commercial,
    PropertyType.building => _building,
    PropertyType.other => _other,
  };

  final PropertyType? type;

  /// The screens of the tunnel for this type, in order (V8 excluded).
  final List<SellerTunnelStep> steps;

  /// Whether the voice agent is offered (V4, V6 mic).
  final bool voice;

  /// Whether the non-certified estimate covers this type (EPIC-05; garages
  /// and outbuildings from single outbuilding sales, owner decision Q5).
  final bool estimate;

  /// V3 · "Construit par vos soins ?".
  final bool asksSelfBuilt;

  /// V3 · precision asked with the type.
  final PropertyTypeDetail detail;

  /// V4b · the questions asked, in the order of the screen.
  final List<TechnicalField> technicalFields;

  /// V4b · the questions that need an answer.
  final Set<TechnicalField> requiredTechnicalFields;

  /// V4b · equipment offered ([TechnicalField.parkingFeatures]).
  final List<ParkingFeature> parkingFeatureChoices;

  /// V6 · noise and overlooking are asked (not for commercial premises).
  final bool asksNeighbourhood;

  /// V5 · the rooms can be skipped ("Passer", type "Autre").
  final bool roomsOptional;

  /// V7 · kinds of documents always listed, in this order (others only
  /// once provided).
  final List<DocumentKind> documentKinds;

  /// Whether [step] is part of the tunnel of this type ([SellerTunnelStep
  /// .submitted] always is).
  bool includes(SellerTunnelStep step) =>
      step == SellerTunnelStep.submitted || steps.contains(step);

  /// The screen after [step]: the next one of this type, V8 after the last.
  SellerTunnelStep nextAfter(SellerTunnelStep step) {
    for (final next in SellerTunnelStep.values.skip(step.index + 1)) {
      if (includes(next)) return next;
    }
    return SellerTunnelStep.submitted;
  }

  /// The screen before [step], or null for the first one and V8 (back then
  /// goes to the seller space).
  SellerTunnelStep? previousBefore(SellerTunnelStep step) {
    if (step == SellerTunnelStep.submitted) return null;
    for (final previous
        in SellerTunnelStep.values.take(step.index).toList().reversed) {
      if (steps.contains(previous)) return previous;
    }
    return null;
  }

  /// The screen where a dossier whose `current_step` is [currentStep]
  /// resumes: the first screen of this type at or after that step.
  SellerTunnelStep resumeAt(int currentStep) {
    for (final step in steps) {
      if (step.number >= currentStep) return step;
    }
    return SellerTunnelStep.submitted;
  }

  /// Progress steps of this type (V5 and V5c count once).
  List<int> get _numbers => [
    for (final step in steps)
      if (!steps.any((s) => s.number == step.number && s.index < step.index))
        step.number,
  ];

  /// Number of progress steps shown in the header ("k/n").
  int get stepCount => _numbers.length;

  /// Position (1-based) of [step] among the progress steps of this type;
  /// [stepCount] for V8 or a step this type skips.
  int positionOf(SellerTunnelStep step) {
    final index = _numbers.indexOf(step.number);
    return index < 0 ? stepCount : index + 1;
  }

  /// Number of progress steps completed when the dossier resumes at
  /// [currentStep].
  int completedAt(int currentStep) =>
      _numbers.where((number) => number < currentStep).length;

  /// The `properties` columns this type does not ask, with their empty
  /// value: kept while the dossier is a draft (the seller may change the
  /// type back), sent with the dossier to clear them.
  Map<String, Object?> get clearedOnSubmit => {
    if (!asksSelfBuilt) PropertyColumns.selfBuilt: null,
    if (detail != PropertyTypeDetail.landKind) PropertyColumns.landKind: null,
    if (detail != PropertyTypeDetail.parkingKind)
      PropertyColumns.parkingKind: null,
    if (detail != PropertyTypeDetail.otherText)
      PropertyColumns.propertyTypeOther: null,
    if (detail != PropertyTypeDetail.commercialUse)
      PropertyColumns.commercialUse: null,
    if (detail != PropertyTypeDetail.unitsCount)
      PropertyColumns.unitsCount: null,
    for (final field in TechnicalField.values)
      if (!technicalFields.contains(field))
        for (final column in field.columns) column: _empty(column),
    if (!steps.contains(SellerTunnelStep.method)) ...{
      PropertyColumns.measurementMethod: null,
      PropertyColumns.annexAreaM2: null,
    },
    if (!steps.contains(SellerTunnelStep.lifestyle) || !asksNeighbourhood) ...{
      PropertyColumns.noiseLevel: null,
      PropertyColumns.overlooking: null,
    },
    if (!steps.contains(SellerTunnelStep.lifestyle))
      PropertyColumns.secretNote: null,
  };

  /// The answers of [property] this type does not ask, emptied: the patch
  /// that clears them when the dossier is sent (only the ones with a
  /// value).
  Map<String, Object?> clearedFrom(Property property) {
    final row = property.toJson();
    return {
      for (final MapEntry(:key, :value) in clearedOnSubmit.entries)
        if (row[key] case final current?
            when current is! List || current.isNotEmpty)
          key: value,
    };
  }

  static Object? _empty(String column) => switch (column) {
    PropertyColumns.heatingSystems ||
    PropertyColumns.outdoorEquipment ||
    PropertyColumns.parkingFeatures => const <String>[],
    _ => null,
  };

  /// Whether each answer counted by the transparency score is given.
  List<bool> scoredAnswers(Property property) {
    final common = [
      property.addressLabel != null,
      property.parcelConfirmed,
      property.propertyType != null,
      property.purchaseYear != null,
    ];
    return switch (type) {
      PropertyType.land => [...common, property.sanitation != null],
      PropertyType.parking => [...common, property.parkingKind != null],
      PropertyType.outbuilding => [...common, property.usableAreaM2 != null],
      PropertyType.commercial => [
        ...common,
        property.usableAreaM2 != null,
        property.constructionYear != null,
      ],
      PropertyType.building => [...common, property.constructionYear != null],
      null ||
      PropertyType.house ||
      PropertyType.apartment ||
      PropertyType.other => [
        ...common,
        property.constructionYear != null,
        property.livingAreaM2 != null,
        property.roomsCount != null,
        property.heatingSystems.isNotEmpty,
        property.sanitation != null,
        property.measurementMethod != null,
        property.noiseLevel != null,
      ],
    };
  }

  @override
  List<Object?> get props => [type];

  // -------------------------------------------------------------------------
  // The table of plan §7.
  // -------------------------------------------------------------------------

  static const List<SellerTunnelStep> _allSteps = [
    SellerTunnelStep.owners,
    SellerTunnelStep.location,
    SellerTunnelStep.context,
    SellerTunnelStep.technical,
    SellerTunnelStep.method,
    SellerTunnelStep.surfaces,
    SellerTunnelStep.lifestyle,
    SellerTunnelStep.documents,
  ];

  /// V1 → V4b, V6, V7 (no rooms).
  static const List<SellerTunnelStep> _withoutRooms = [
    SellerTunnelStep.owners,
    SellerTunnelStep.location,
    SellerTunnelStep.context,
    SellerTunnelStep.technical,
    SellerTunnelStep.lifestyle,
    SellerTunnelStep.documents,
  ];

  /// V1 → V4b, V7 (no rooms, no neighbourhood).
  static const List<SellerTunnelStep> _short = [
    SellerTunnelStep.owners,
    SellerTunnelStep.location,
    SellerTunnelStep.context,
    SellerTunnelStep.technical,
    SellerTunnelStep.documents,
  ];

  static const List<TechnicalField> _dwellingFields = [
    TechnicalField.constructionYear,
    TechnicalField.exposure,
    TechnicalField.livingArea,
    TechnicalField.livingRoomArea,
    TechnicalField.rooms,
    TechnicalField.levels,
    TechnicalField.wallMaterial,
    TechnicalField.adjacency,
    TechnicalField.roof,
    TechnicalField.heating,
    TechnicalField.sanitation,
    TechnicalField.outdoorEquipment,
  ];

  static const List<DocumentKind> _dwellingDocuments = [
    DocumentKind.titleDeed,
    DocumentKind.propertyTax,
    DocumentKind.energyBills,
    DocumentKind.worksInvoice,
    DocumentKind.identityDocument,
    DocumentKind.diagnostics,
    DocumentKind.sanitationReport,
    DocumentKind.other,
  ];

  static const _undecided = PropertyTypeProfile._(
    type: null,
    steps: _allSteps,
    voice: true,
    estimate: false,
    asksSelfBuilt: true,
    detail: PropertyTypeDetail.none,
    technicalFields: _dwellingFields,
    requiredTechnicalFields: {
      TechnicalField.constructionYear,
      TechnicalField.livingArea,
    },
  );

  static const _house = PropertyTypeProfile._(
    type: PropertyType.house,
    steps: _allSteps,
    voice: true,
    estimate: true,
    asksSelfBuilt: true,
    detail: PropertyTypeDetail.none,
    technicalFields: _dwellingFields,
    requiredTechnicalFields: {
      TechnicalField.constructionYear,
      TechnicalField.livingArea,
      TechnicalField.levels,
      TechnicalField.heating,
    },
  );

  static const _apartment = PropertyTypeProfile._(
    type: PropertyType.apartment,
    steps: _allSteps,
    voice: true,
    estimate: true,
    asksSelfBuilt: true,
    detail: PropertyTypeDetail.none,
    technicalFields: [
      TechnicalField.constructionYear,
      TechnicalField.exposure,
      TechnicalField.livingArea,
      TechnicalField.livingRoomArea,
      TechnicalField.rooms,
      TechnicalField.wallMaterial,
      TechnicalField.heating,
      TechnicalField.sanitation,
      TechnicalField.outdoorEquipment,
    ],
    requiredTechnicalFields: {
      TechnicalField.constructionYear,
      TechnicalField.livingArea,
      TechnicalField.heating,
    },
  );

  static const _land = PropertyTypeProfile._(
    type: PropertyType.land,
    steps: _withoutRooms,
    voice: false,
    estimate: false,
    asksSelfBuilt: false,
    detail: PropertyTypeDetail.landKind,
    technicalFields: [
      TechnicalField.sanitation,
      TechnicalField.outdoorEquipment,
    ],
    requiredTechnicalFields: {},
    documentKinds: [
      DocumentKind.titleDeed,
      DocumentKind.propertyTax,
      DocumentKind.identityDocument,
      DocumentKind.sanitationReport,
      DocumentKind.plan,
      DocumentKind.other,
    ],
  );

  static const _parking = PropertyTypeProfile._(
    type: PropertyType.parking,
    steps: _short,
    voice: false,
    estimate: true,
    asksSelfBuilt: false,
    detail: PropertyTypeDetail.parkingKind,
    technicalFields: [
      TechnicalField.usableArea,
      TechnicalField.parkingLevel,
      TechnicalField.parkingFeatures,
    ],
    requiredTechnicalFields: {},
    parkingFeatureChoices: ParkingFeature.values,
    documentKinds: [
      DocumentKind.titleDeed,
      DocumentKind.propertyTax,
      DocumentKind.identityDocument,
      DocumentKind.other,
    ],
  );

  static const _outbuilding = PropertyTypeProfile._(
    type: PropertyType.outbuilding,
    steps: _short,
    voice: false,
    estimate: true,
    asksSelfBuilt: true,
    detail: PropertyTypeDetail.otherText,
    technicalFields: [
      TechnicalField.usableArea,
      TechnicalField.constructionYear,
      TechnicalField.parkingFeatures,
    ],
    requiredTechnicalFields: {},
    parkingFeatureChoices: [ParkingFeature.electricity, ParkingFeature.water],
    documentKinds: [
      DocumentKind.titleDeed,
      DocumentKind.propertyTax,
      DocumentKind.identityDocument,
      DocumentKind.plan,
      DocumentKind.other,
    ],
  );

  static const _commercial = PropertyTypeProfile._(
    type: PropertyType.commercial,
    steps: _withoutRooms,
    voice: false,
    estimate: false,
    asksSelfBuilt: false,
    detail: PropertyTypeDetail.commercialUse,
    technicalFields: [
      TechnicalField.usableArea,
      TechnicalField.constructionYear,
      TechnicalField.heating,
    ],
    requiredTechnicalFields: {TechnicalField.usableArea},
    asksNeighbourhood: false,
    documentKinds: [
      DocumentKind.titleDeed,
      DocumentKind.propertyTax,
      DocumentKind.identityDocument,
      DocumentKind.diagnostics,
      DocumentKind.energyBills,
      DocumentKind.other,
    ],
  );

  static const _building = PropertyTypeProfile._(
    type: PropertyType.building,
    steps: _withoutRooms,
    voice: false,
    estimate: false,
    asksSelfBuilt: false,
    detail: PropertyTypeDetail.unitsCount,
    technicalFields: [
      TechnicalField.constructionYear,
      TechnicalField.wallMaterial,
      TechnicalField.roof,
      TechnicalField.heating,
      TechnicalField.sanitation,
    ],
    requiredTechnicalFields: {TechnicalField.constructionYear},
    documentKinds: [
      DocumentKind.titleDeed,
      DocumentKind.propertyTax,
      DocumentKind.identityDocument,
      DocumentKind.diagnostics,
      DocumentKind.worksInvoice,
      DocumentKind.sanitationReport,
      DocumentKind.other,
    ],
  );

  static const _other = PropertyTypeProfile._(
    type: PropertyType.other,
    roomsOptional: true,
    steps: _allSteps,
    voice: true,
    estimate: false,
    asksSelfBuilt: true,
    detail: PropertyTypeDetail.otherText,
    technicalFields: _dwellingFields,
    requiredTechnicalFields: {
      TechnicalField.constructionYear,
      TechnicalField.livingArea,
    },
  );
}
