import 'package:equatable/equatable.dart';
import 'package:property_repository/src/models/enums.dart';
import 'package:property_repository/src/models/json.dart';

/// Adds `id` to [row] when it is known (new rows get one from Postgres).
Map<String, Object?> _withId(String? id, Map<String, Object?> row) => {
  'id': ?id,
  ...row,
};

/// A `field_sources` column as read (EPIC-16).
Map<String, Object?> _sources(Object? json) =>
    Map<String, Object?>.unmodifiable(
      json as Map<String, dynamic>? ?? const {},
    );

/// [row] with its `field_sources` when known: an upsert without them keeps
/// the stored ones.
Map<String, Object?> _withSources(
  Map<String, Object?> sources,
  Map<String, Object?> row,
) => {...row, if (sources.isNotEmpty) 'field_sources': sources};

/// {@template property_owner}
/// V1 · an owner of the property (`property_owners`); position 1 is the
/// signed-in user.
/// {@endtemplate}
class PropertyOwner extends Equatable {
  /// {@macro property_owner}
  const new({
    required this.propertyId,
    required this.position,
    required this.firstName,
    required this.lastName,
    this.id,
    this.profileId,
    this.phone,
    this.email,
  });

  /// Builds an owner from a `property_owners` row.
  factory fromJson(Map<String, dynamic> json) => PropertyOwner(
    id: json['id'] as String?,
    propertyId: json['property_id'] as String,
    position: readInt(json['position'])!,
    profileId: json['profile_id'] as String?,
    firstName: json['first_name'] as String,
    lastName: json['last_name'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
  );

  /// Null until saved.
  final String? id;
  final String propertyId;

  /// 1 for the user, then 2, 3… for co-owners.
  final int position;
  final String? profileId;
  final String firstName;
  final String lastName;

  /// E.164 phone number.
  final String? phone;
  final String? email;

  /// The row of this owner.
  Map<String, Object?> toJson() => _withId(id, {
    'property_id': propertyId,
    'position': position,
    'profile_id': profileId,
    'first_name': firstName,
    'last_name': lastName,
    'phone': phone,
    'email': email,
  });

  @override
  List<Object?> get props => [
    id,
    propertyId,
    position,
    profileId,
    firstName,
    lastName,
    phone,
    email,
  ];
}

/// {@template property_parcel}
/// V2 · a cadastral parcel of the property (`property_parcels`).
/// {@endtemplate}
class PropertyParcel extends Equatable {
  /// {@macro property_parcel}
  const new({
    required this.propertyId,
    required this.idu,
    this.id,
    this.codeInsee,
    this.section,
    this.numero,
    this.areaM2,
    this.geometry,
    this.source = 'apicarto',
  });

  /// Builds a parcel from a `property_parcels` row.
  factory fromJson(Map<String, dynamic> json) => PropertyParcel(
    id: json['id'] as String?,
    propertyId: json['property_id'] as String,
    idu: json['idu'] as String,
    codeInsee: json['code_insee'] as String?,
    section: json['section'] as String?,
    numero: json['numero'] as String?,
    areaM2: readInt(json['area_m2']),
    geometry: json['geometry'] as Map<String, dynamic>?,
    source: json['source'] as String? ?? 'apicarto',
  );

  final String? id;
  final String propertyId;

  /// 14-character cadastre identifier.
  final String idu;
  final String? codeInsee;
  final String? section;
  final String? numero;

  /// Contenance (m²).
  final int? areaM2;

  /// GeoJSON geometry (MultiPolygon).
  final Map<String, dynamic>? geometry;
  final String source;

  /// The row of this parcel.
  Map<String, Object?> toJson() => _withId(id, {
    'property_id': propertyId,
    'idu': idu,
    'code_insee': codeInsee,
    'section': section,
    'numero': numero,
    'area_m2': areaM2,
    'geometry': geometry,
    'source': source,
  });

  @override
  List<Object?> get props => [
    id,
    propertyId,
    idu,
    codeInsee,
    section,
    numero,
    areaM2,
    geometry,
    source,
  ];
}

/// {@template previous_estimate}
/// V3 · an estimate made by an agency (`previous_estimates`).
/// {@endtemplate}
class PreviousEstimate extends Equatable {
  /// {@macro previous_estimate}
  const new({
    required this.propertyId,
    required this.priceEur,
    this.id,
    this.estimatedMonth,
    this.agencyName,
    this.source = EstimateSource.manual,
    this.fieldSources = const {},
  });

  /// Builds an estimate from a `previous_estimates` row.
  factory fromJson(Map<String, dynamic> json) => PreviousEstimate(
    id: json['id'] as String?,
    propertyId: json['property_id'] as String,
    priceEur: readInt(json['price_eur'])!,
    estimatedMonth: readDateTime(json['estimated_month']),
    agencyName: json['agency_name'] as String?,
    source:
        parseDbEnum(EstimateSource.values, json['source']) ??
        EstimateSource.manual,
    fieldSources: _sources(json['field_sources']),
  );

  final String? id;
  final String propertyId;
  final int priceEur;

  /// Month of the estimate (day ignored).
  final DateTime? estimatedMonth;
  final String? agencyName;

  /// Typed or dictated (EPIC-16).
  final EstimateSource source;

  /// Origin of each value (column → `FieldSource` JSON), EPIC-16.
  final Map<String, Object?> fieldSources;

  /// The row of this estimate.
  Map<String, Object?> toJson() => _withId(
    id,
    _withSources(fieldSources, {
      'property_id': propertyId,
      'price_eur': priceEur,
      'estimated_month': estimatedMonth == null
          ? null
          : encodeMonth(estimatedMonth!),
      'agency_name': agencyName,
      'source': source.value,
    }),
  );

  @override
  List<Object?> get props => [
    id,
    propertyId,
    priceEur,
    estimatedMonth,
    agencyName,
    source,
    fieldSources,
  ];
}

/// {@template room}
/// V5c · a room and its surface (`rooms`).
/// {@endtemplate}
class Room extends Equatable {
  /// {@macro room}
  const new({
    required this.propertyId,
    required this.name,
    required this.areaM2,
    this.id,
    this.level,
    this.sortOrder = 0,
    this.ceilingHeightM,
    this.floorCovering,
    this.glazing,
    this.isMain = false,
    this.isAnnex = false,
    this.source = RoomSource.manual,
    this.photosCount = 0,
    this.scanData,
    this.description,
    this.fieldSources = const {},
  });

  /// Builds a room from a `rooms` row.
  factory fromJson(Map<String, dynamic> json) => Room(
    id: json['id'] as String?,
    propertyId: json['property_id'] as String,
    name: json['name'] as String,
    level: parseDbEnum(RoomLevel.values, json['level']),
    sortOrder: readInt(json['sort_order']) ?? 0,
    areaM2: readDouble(json['area_m2'])!,
    ceilingHeightM: readDouble(json['ceiling_height_m']),
    floorCovering: json['floor_covering'] as String?,
    glazing: parseDbEnum(Glazing.values, json['glazing']),
    isMain: json['is_main'] as bool? ?? false,
    isAnnex: json['is_annex'] as bool? ?? false,
    source: parseDbEnum(RoomSource.values, json['source']) ?? RoomSource.manual,
    photosCount: readInt(json['photos_count']) ?? 0,
    scanData: json['scan_data'] as Map<String, dynamic>?,
    description: json['description'] as String?,
    fieldSources: _sources(json['field_sources']),
  );

  final String? id;
  final String propertyId;
  final String name;
  final RoomLevel? level;
  final int sortOrder;
  final double areaM2;
  final double? ceilingHeightM;
  final String? floorCovering;
  final Glazing? glazing;

  /// Pièce principale (living room, bedroom, office…).
  final bool isMain;

  /// Annexe (garage, cellier…): not part of the living area.
  final bool isAnnex;
  final RoomSource source;
  final int photosCount;
  final Map<String, dynamic>? scanData;

  /// « Notes complémentaires » (≤ [descriptionMaxLength] characters),
  /// typed, dictated (EPIC-14, EPIC-16) or added from a photo (EPIC-15).
  final String? description;

  /// Origin of each value (column → `FieldSource` JSON), EPIC-16.
  final Map<String, Object?> fieldSources;

  /// Maximum length of [description] (`rooms.description`).
  static const descriptionMaxLength = 600;

  /// The row of this room.
  Map<String, Object?> toJson() => _withId(
    id,
    _withSources(fieldSources, {
      'property_id': propertyId,
      'name': name,
      'level': level?.value,
      'sort_order': sortOrder,
      'area_m2': areaM2,
      'ceiling_height_m': ceilingHeightM,
      'floor_covering': floorCovering,
      'glazing': glazing?.value,
      'is_main': isMain,
      'is_annex': isAnnex,
      'source': source.value,
      'photos_count': photosCount,
      'scan_data': scanData,
      'description': description,
    }),
  );

  @override
  List<Object?> get props => [
    id,
    propertyId,
    name,
    level,
    sortOrder,
    areaM2,
    ceilingHeightM,
    floorCovering,
    glazing,
    isMain,
    isAnnex,
    source,
    photosCount,
    scanData,
    description,
    fieldSources,
  ];
}

/// {@template lifestyle_item}
/// V6 · an asset or a watch point of the neighbourhood
/// (`lifestyle_items`).
/// {@endtemplate}
class LifestyleItem extends Equatable {
  /// {@macro lifestyle_item}
  const new({
    required this.propertyId,
    required this.kind,
    required this.label,
    this.id,
    this.sortOrder = 0,
    this.source = LifestyleItemSource.declared,
    this.fieldSources = const {},
  });

  /// Builds an item from a `lifestyle_items` row.
  factory fromJson(Map<String, dynamic> json) => LifestyleItem(
    id: json['id'] as String?,
    propertyId: json['property_id'] as String,
    kind:
        parseDbEnum(LifestyleItemKind.values, json['kind']) ??
        LifestyleItemKind.asset,
    label: json['label'] as String,
    sortOrder: readInt(json['sort_order']) ?? 0,
    source:
        parseDbEnum(LifestyleItemSource.values, json['source']) ??
        LifestyleItemSource.declared,
    fieldSources: _sources(json['field_sources']),
  );

  final String? id;
  final String propertyId;
  final LifestyleItemKind kind;
  final String label;
  final int sortOrder;
  final LifestyleItemSource source;

  /// Origin of the label (`label` → `FieldSource` JSON), EPIC-16.
  final Map<String, Object?> fieldSources;

  /// The row of this item.
  Map<String, Object?> toJson() => _withId(
    id,
    _withSources(fieldSources, {
      'property_id': propertyId,
      'kind': kind.value,
      'label': label,
      'sort_order': sortOrder,
      'source': source.value,
    }),
  );

  @override
  List<Object?> get props => [
    id,
    propertyId,
    kind,
    label,
    sortOrder,
    source,
    fieldSources,
  ];
}

/// {@template property_document}
/// V7 · a document of the dossier (`property_documents`); the file lives in
/// the private `property-documents` Storage bucket at [storagePath].
/// {@endtemplate}
class PropertyDocument extends Equatable {
  /// {@macro property_document}
  const new({
    required this.id,
    required this.propertyId,
    required this.kind,
    required this.storagePath,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.status = DocumentStatus.received,
    this.extracted,
    this.uploadedAt,
  });

  /// Builds a document from a `property_documents` row.
  factory fromJson(Map<String, dynamic> json) => PropertyDocument(
    id: json['id'] as String,
    propertyId: json['property_id'] as String,
    kind: parseDbEnum(DocumentKind.values, json['kind']) ?? DocumentKind.other,
    storagePath: json['storage_path'] as String,
    fileName: json['file_name'] as String?,
    mimeType: json['mime_type'] as String?,
    sizeBytes: readInt(json['size_bytes']),
    status:
        parseDbEnum(DocumentStatus.values, json['status']) ??
        DocumentStatus.received,
    extracted: json['extracted'] as Map<String, dynamic>?,
    uploadedAt: readDateTime(json['uploaded_at']),
  );

  final String id;
  final String propertyId;
  final DocumentKind kind;

  /// `<owner id>/<property id>/<file>` in the `property-documents` bucket.
  final String storagePath;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;
  final DocumentStatus status;

  /// Data extracted by the analysis (later).
  final Map<String, dynamic>? extracted;
  final DateTime? uploadedAt;

  /// The row of this document.
  Map<String, Object?> toJson() => {
    'id': id,
    'property_id': propertyId,
    'kind': kind.value,
    'storage_path': storagePath,
    'file_name': fileName,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'status': status.value,
    'extracted': extracted,
    'uploaded_at': encodeDbValue(uploadedAt),
  };

  @override
  List<Object?> get props => [
    id,
    propertyId,
    kind,
    storagePath,
    fileName,
    mimeType,
    sizeBytes,
    status,
    extracted,
    uploadedAt,
  ];
}
