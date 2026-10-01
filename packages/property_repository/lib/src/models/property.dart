import 'package:equatable/equatable.dart';
import 'package:property_repository/src/models/enums.dart';
import 'package:property_repository/src/models/json.dart';

/// Column names of the `properties` table, to build the patches given to
/// `PropertyRepository.updateProperty`.
abstract final class PropertyColumns {
  static const id = 'id';
  static const ownerId = 'owner_id';
  static const status = 'status';
  static const currentStep = 'current_step';
  static const ownershipType = 'ownership_type';
  static const addressLabel = 'address_label';
  static const addressHousenumber = 'address_housenumber';
  static const addressStreet = 'address_street';
  static const addressPostcode = 'address_postcode';
  static const addressCity = 'address_city';
  static const addressCitycode = 'address_citycode';
  static const addressBanId = 'address_ban_id';
  static const lat = 'lat';
  static const lng = 'lng';
  static const parcelConfirmed = 'parcel_confirmed';
  static const specialSituations = 'special_situations';
  static const specialSituationOther = 'special_situation_other';
  static const propertyType = 'property_type';
  static const propertyTypeOther = 'property_type_other';
  static const purchaseYear = 'purchase_year';
  static const purchasePriceEur = 'purchase_price_eur';
  static const selfBuilt = 'self_built';
  static const saleReason = 'sale_reason';
  static const previouslyEstimated = 'previously_estimated';
  static const constructionYear = 'construction_year';
  static const orientation = 'orientation';
  static const livingAreaM2 = 'living_area_m2';
  static const livingRoomAreaM2 = 'living_room_area_m2';
  static const annexAreaM2 = 'annex_area_m2';
  static const roomsCount = 'rooms_count';
  static const bedroomsCount = 'bedrooms_count';
  static const levels = 'levels';
  static const wallMaterial = 'wall_material';
  static const adjacency = 'adjacency';
  static const roofType = 'roof_type';
  static const roofYear = 'roof_year';
  static const heatingEnergy = 'heating_energy';
  static const heatPumpType = 'heat_pump_type';
  static const heatPumpYear = 'heat_pump_year';
  static const sanitation = 'sanitation';
  static const outdoorEquipment = 'outdoor_equipment';
  static const poolType = 'pool_type';
  static const poolLengthM = 'pool_length_m';
  static const poolWidthM = 'pool_width_m';
  static const measurementMethod = 'measurement_method';
  static const noiseLevel = 'noise_level';
  static const overlooking = 'overlooking';
  static const secretNote = 'secret_note';
  static const provenance = 'provenance';
  static const transparencyScore = 'transparency_score';
  static const submittedAt = 'submitted_at';
  static const notifyPush = 'notify_push';
  static const aiEstimateLowEur = 'ai_estimate_low_eur';
  static const aiEstimateMedianEur = 'ai_estimate_median_eur';
  static const aiEstimateHighEur = 'ai_estimate_high_eur';
  static const aiEstimateComputedAt = 'ai_estimate_computed_at';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// {@template property}
/// A seller dossier (row of the `properties` table), filled step by step
/// in the seller tunnel. Every answer is nullable until given.
/// {@endtemplate}
class Property extends Equatable {
  /// {@macro property}
  const new({
    required this.id,
    required this.ownerId,
    this.status = PropertyStatus.draft,
    this.currentStep = 1,
    this.ownershipType,
    this.addressLabel,
    this.addressHousenumber,
    this.addressStreet,
    this.addressPostcode,
    this.addressCity,
    this.addressCitycode,
    this.addressBanId,
    this.lat,
    this.lng,
    this.parcelConfirmed = false,
    this.specialSituations = const [],
    this.specialSituationOther,
    this.propertyType,
    this.propertyTypeOther,
    this.purchaseYear,
    this.purchasePriceEur,
    this.selfBuilt,
    this.saleReason,
    this.previouslyEstimated,
    this.constructionYear,
    this.orientation,
    this.livingAreaM2,
    this.livingRoomAreaM2,
    this.annexAreaM2,
    this.roomsCount,
    this.bedroomsCount,
    this.levels,
    this.wallMaterial,
    this.adjacency,
    this.roofType,
    this.roofYear,
    this.heatingEnergy,
    this.heatPumpType,
    this.heatPumpYear,
    this.sanitation,
    this.outdoorEquipment = const [],
    this.poolType,
    this.poolLengthM,
    this.poolWidthM,
    this.measurementMethod,
    this.noiseLevel,
    this.overlooking,
    this.secretNote,
    this.provenance = const {},
    this.transparencyScore,
    this.submittedAt,
    this.notifyPush = true,
    this.aiEstimateLowEur,
    this.aiEstimateMedianEur,
    this.aiEstimateHighEur,
    this.aiEstimateComputedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Builds a property from a `properties` row.
  factory fromJson(Map<String, dynamic> json) {
    return Property(
      id: json[PropertyColumns.id] as String,
      ownerId: json[PropertyColumns.ownerId] as String,
      status:
          parseDbEnum(PropertyStatus.values, json[PropertyColumns.status]) ??
          PropertyStatus.draft,
      currentStep: readInt(json[PropertyColumns.currentStep]) ?? 1,
      ownershipType: parseDbEnum(
        OwnershipType.values,
        json[PropertyColumns.ownershipType],
      ),
      addressLabel: json[PropertyColumns.addressLabel] as String?,
      addressHousenumber: json[PropertyColumns.addressHousenumber] as String?,
      addressStreet: json[PropertyColumns.addressStreet] as String?,
      addressPostcode: json[PropertyColumns.addressPostcode] as String?,
      addressCity: json[PropertyColumns.addressCity] as String?,
      addressCitycode: json[PropertyColumns.addressCitycode] as String?,
      addressBanId: json[PropertyColumns.addressBanId] as String?,
      lat: readDouble(json[PropertyColumns.lat]),
      lng: readDouble(json[PropertyColumns.lng]),
      parcelConfirmed: json[PropertyColumns.parcelConfirmed] as bool? ?? false,
      specialSituations: parseDbEnumList(
        SpecialSituation.values,
        json[PropertyColumns.specialSituations],
      ),
      specialSituationOther:
          json[PropertyColumns.specialSituationOther] as String?,
      propertyType: parseDbEnum(
        PropertyType.values,
        json[PropertyColumns.propertyType],
      ),
      propertyTypeOther: json[PropertyColumns.propertyTypeOther] as String?,
      purchaseYear: readInt(json[PropertyColumns.purchaseYear]),
      purchasePriceEur: readInt(json[PropertyColumns.purchasePriceEur]),
      selfBuilt: json[PropertyColumns.selfBuilt] as bool?,
      saleReason: parseDbEnum(
        SaleReason.values,
        json[PropertyColumns.saleReason],
      ),
      previouslyEstimated: json[PropertyColumns.previouslyEstimated] as bool?,
      constructionYear: readInt(json[PropertyColumns.constructionYear]),
      orientation: json[PropertyColumns.orientation] as String?,
      livingAreaM2: readDouble(json[PropertyColumns.livingAreaM2]),
      livingRoomAreaM2: readDouble(json[PropertyColumns.livingRoomAreaM2]),
      annexAreaM2: readDouble(json[PropertyColumns.annexAreaM2]),
      roomsCount: readInt(json[PropertyColumns.roomsCount]),
      bedroomsCount: readInt(json[PropertyColumns.bedroomsCount]),
      levels: parseDbEnum(PropertyLevels.values, json[PropertyColumns.levels]),
      wallMaterial: parseDbEnum(
        WallMaterial.values,
        json[PropertyColumns.wallMaterial],
      ),
      adjacency: parseDbEnum(Adjacency.values, json[PropertyColumns.adjacency]),
      roofType: json[PropertyColumns.roofType] as String?,
      roofYear: readInt(json[PropertyColumns.roofYear]),
      heatingEnergy: parseDbEnum(
        HeatingEnergy.values,
        json[PropertyColumns.heatingEnergy],
      ),
      heatPumpType: json[PropertyColumns.heatPumpType] as String?,
      heatPumpYear: readInt(json[PropertyColumns.heatPumpYear]),
      sanitation: parseDbEnum(
        Sanitation.values,
        json[PropertyColumns.sanitation],
      ),
      outdoorEquipment: parseDbEnumList(
        OutdoorEquipment.values,
        json[PropertyColumns.outdoorEquipment],
      ),
      poolType: json[PropertyColumns.poolType] as String?,
      poolLengthM: readDouble(json[PropertyColumns.poolLengthM]),
      poolWidthM: readDouble(json[PropertyColumns.poolWidthM]),
      measurementMethod: parseDbEnum(
        MeasurementMethod.values,
        json[PropertyColumns.measurementMethod],
      ),
      noiseLevel: readInt(json[PropertyColumns.noiseLevel]),
      overlooking: parseDbEnum(
        Overlooking.values,
        json[PropertyColumns.overlooking],
      ),
      secretNote: json[PropertyColumns.secretNote] as String?,
      provenance: Map<String, Object?>.unmodifiable(
        json[PropertyColumns.provenance] as Map<String, dynamic>? ?? const {},
      ),
      transparencyScore: readInt(json[PropertyColumns.transparencyScore]),
      submittedAt: readDateTime(json[PropertyColumns.submittedAt]),
      notifyPush: json[PropertyColumns.notifyPush] as bool? ?? true,
      aiEstimateLowEur: readInt(json[PropertyColumns.aiEstimateLowEur]),
      aiEstimateMedianEur: readInt(json[PropertyColumns.aiEstimateMedianEur]),
      aiEstimateHighEur: readInt(json[PropertyColumns.aiEstimateHighEur]),
      aiEstimateComputedAt: readDateTime(
        json[PropertyColumns.aiEstimateComputedAt],
      ),
      createdAt: readDateTime(json[PropertyColumns.createdAt]),
      updatedAt: readDateTime(json[PropertyColumns.updatedAt]),
    );
  }

  /// Number of steps of the tunnel (V1 → V7).
  static const stepCount = 7;

  final String id;
  final String ownerId;
  final PropertyStatus status;

  /// Resume point: 1–7 = V1–V7, 8 once submitted.
  final int currentStep;

  final OwnershipType? ownershipType;
  final String? addressLabel;
  final String? addressHousenumber;
  final String? addressStreet;
  final String? addressPostcode;
  final String? addressCity;

  /// INSEE code of the city.
  final String? addressCitycode;

  /// Identifier of the address in the Base Adresse Nationale.
  final String? addressBanId;
  final double? lat;
  final double? lng;
  final bool parcelConfirmed;
  final List<SpecialSituation> specialSituations;
  final String? specialSituationOther;
  final PropertyType? propertyType;
  final String? propertyTypeOther;
  final int? purchaseYear;
  final int? purchasePriceEur;
  final bool? selfBuilt;
  final SaleReason? saleReason;
  final bool? previouslyEstimated;
  final int? constructionYear;
  final String? orientation;
  final double? livingAreaM2;
  final double? livingRoomAreaM2;

  /// Surface of the annexes (garage, cellier…), not part of
  /// [livingAreaM2].
  final double? annexAreaM2;
  final int? roomsCount;
  final int? bedroomsCount;
  final PropertyLevels? levels;
  final WallMaterial? wallMaterial;
  final Adjacency? adjacency;
  final String? roofType;
  final int? roofYear;
  final HeatingEnergy? heatingEnergy;
  final String? heatPumpType;
  final int? heatPumpYear;
  final Sanitation? sanitation;
  final List<OutdoorEquipment> outdoorEquipment;
  final String? poolType;
  final double? poolLengthM;
  final double? poolWidthM;
  final MeasurementMethod? measurementMethod;

  /// 1 (very calm) → 10 (very noisy).
  final int? noiseLevel;
  final Overlooking? overlooking;
  final String? secretNote;

  /// Raw provenance map (column → value); see [provenanceOf].
  final Map<String, Object?> provenance;

  /// 0–100.
  final int? transparencyScore;
  final DateTime? submittedAt;
  final bool notifyPush;
  final int? aiEstimateLowEur;
  final int? aiEstimateMedianEur;
  final int? aiEstimateHighEur;
  final DateTime? aiEstimateComputedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Provenance of [column] (a [PropertyColumns] name), stored either as a
  /// value (`"document"`) or as an object with a `source` key. Answers with
  /// no recorded provenance are [Provenance.declared].
  Provenance provenanceOf(String column) {
    final raw = provenance[column];
    final value = raw is Map ? raw['source'] : raw;
    return parseDbEnum(Provenance.values, value) ?? Provenance.declared;
  }

  /// The [provenance] map with [updates] (column → [Provenance]) applied,
  /// to send as the `provenance` column of a patch; other entries are kept.
  Map<String, Object?> mergeProvenance(Map<String, Provenance> updates) => {
    ...provenance,
    for (final MapEntry(:key, :value) in updates.entries) key: value.value,
  };

  /// The row of this property, as stored (including columns the app may not
  /// write: never send it as an update).
  Map<String, Object?> toJson() {
    return {
      PropertyColumns.id: id,
      PropertyColumns.ownerId: ownerId,
      PropertyColumns.status: status.value,
      PropertyColumns.currentStep: currentStep,
      PropertyColumns.ownershipType: ownershipType?.value,
      PropertyColumns.addressLabel: addressLabel,
      PropertyColumns.addressHousenumber: addressHousenumber,
      PropertyColumns.addressStreet: addressStreet,
      PropertyColumns.addressPostcode: addressPostcode,
      PropertyColumns.addressCity: addressCity,
      PropertyColumns.addressCitycode: addressCitycode,
      PropertyColumns.addressBanId: addressBanId,
      PropertyColumns.lat: lat,
      PropertyColumns.lng: lng,
      PropertyColumns.parcelConfirmed: parcelConfirmed,
      PropertyColumns.specialSituations: encodeDbValue(specialSituations),
      PropertyColumns.specialSituationOther: specialSituationOther,
      PropertyColumns.propertyType: propertyType?.value,
      PropertyColumns.propertyTypeOther: propertyTypeOther,
      PropertyColumns.purchaseYear: purchaseYear,
      PropertyColumns.purchasePriceEur: purchasePriceEur,
      PropertyColumns.selfBuilt: selfBuilt,
      PropertyColumns.saleReason: saleReason?.value,
      PropertyColumns.previouslyEstimated: previouslyEstimated,
      PropertyColumns.constructionYear: constructionYear,
      PropertyColumns.orientation: orientation,
      PropertyColumns.livingAreaM2: livingAreaM2,
      PropertyColumns.livingRoomAreaM2: livingRoomAreaM2,
      PropertyColumns.annexAreaM2: annexAreaM2,
      PropertyColumns.roomsCount: roomsCount,
      PropertyColumns.bedroomsCount: bedroomsCount,
      PropertyColumns.levels: levels?.value,
      PropertyColumns.wallMaterial: wallMaterial?.value,
      PropertyColumns.adjacency: adjacency?.value,
      PropertyColumns.roofType: roofType,
      PropertyColumns.roofYear: roofYear,
      PropertyColumns.heatingEnergy: heatingEnergy?.value,
      PropertyColumns.heatPumpType: heatPumpType,
      PropertyColumns.heatPumpYear: heatPumpYear,
      PropertyColumns.sanitation: sanitation?.value,
      PropertyColumns.outdoorEquipment: encodeDbValue(outdoorEquipment),
      PropertyColumns.poolType: poolType,
      PropertyColumns.poolLengthM: poolLengthM,
      PropertyColumns.poolWidthM: poolWidthM,
      PropertyColumns.measurementMethod: measurementMethod?.value,
      PropertyColumns.noiseLevel: noiseLevel,
      PropertyColumns.overlooking: overlooking?.value,
      PropertyColumns.secretNote: secretNote,
      PropertyColumns.provenance: provenance,
      PropertyColumns.transparencyScore: transparencyScore,
      PropertyColumns.submittedAt: encodeDbValue(submittedAt),
      PropertyColumns.notifyPush: notifyPush,
      PropertyColumns.aiEstimateLowEur: aiEstimateLowEur,
      PropertyColumns.aiEstimateMedianEur: aiEstimateMedianEur,
      PropertyColumns.aiEstimateHighEur: aiEstimateHighEur,
      PropertyColumns.aiEstimateComputedAt: encodeDbValue(aiEstimateComputedAt),
      PropertyColumns.createdAt: encodeDbValue(createdAt),
      PropertyColumns.updatedAt: encodeDbValue(updatedAt),
    };
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    status,
    currentStep,
    ownershipType,
    addressLabel,
    addressHousenumber,
    addressStreet,
    addressPostcode,
    addressCity,
    addressCitycode,
    addressBanId,
    lat,
    lng,
    parcelConfirmed,
    specialSituations,
    specialSituationOther,
    propertyType,
    propertyTypeOther,
    purchaseYear,
    purchasePriceEur,
    selfBuilt,
    saleReason,
    previouslyEstimated,
    constructionYear,
    orientation,
    livingAreaM2,
    livingRoomAreaM2,
    annexAreaM2,
    roomsCount,
    bedroomsCount,
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
    poolLengthM,
    poolWidthM,
    measurementMethod,
    noiseLevel,
    overlooking,
    secretNote,
    provenance,
    transparencyScore,
    submittedAt,
    notifyPush,
    aiEstimateLowEur,
    aiEstimateMedianEur,
    aiEstimateHighEur,
    aiEstimateComputedAt,
    createdAt,
    updatedAt,
  ];
}
