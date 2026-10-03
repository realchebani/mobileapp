import 'package:backoffice_repository/src/models/dossier_summary.dart';
import 'package:backoffice_repository/src/models/json.dart';
import 'package:backoffice_repository/src/models/staff.dart';
import 'package:backoffice_repository/src/models/valuation_draft.dart';
import 'package:equatable/equatable.dart';

/// {@template dossier_owner}
/// An owner of the property. A partner only gets [initials] and [city].
/// {@endtemplate}
class DossierOwner extends Equatable {
  /// {@macro dossier_owner}
  const new({
    required this.id,
    required this.position,
    this.firstName,
    this.lastName,
    this.phone,
    this.email,
    this.initials,
    this.city,
    this.identityVerifiedAt,
  });

  factory fromJson(JsonMap json) => DossierOwner(
    id: json['id'] as String,
    position: Json.integer(json['position']) ?? 0,
    firstName: Json.text(json['first_name']),
    lastName: Json.text(json['last_name']),
    phone: Json.text(json['phone']),
    email: Json.text(json['email']),
    initials: Json.text(json['initials']),
    city: Json.text(json['city']),
    identityVerifiedAt: Json.date(json['identity_verified_at']),
  );

  final String id;
  final int position;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String? initials;
  final String? city;
  final DateTime? identityVerifiedAt;

  /// Whether the caller sees the identity (admin, expert).
  bool get isMasked => firstName == null && lastName == null;

  String get displayName => isMasked
      ? [initials, city].whereType<String>().join(' · ')
      : [firstName, lastName].whereType<String>().join(' ');

  @override
  List<Object?> get props => [
    id,
    position,
    firstName,
    lastName,
    phone,
    email,
    initials,
    city,
    identityVerifiedAt,
  ];
}

/// {@template dossier_document}
/// A document of the dossier (no storage path: open it through bo-files).
/// {@endtemplate}
class DossierDocument extends Equatable {
  /// {@macro dossier_document}
  const new({
    required this.id,
    required this.kind,
    required this.status,
    this.title,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.uploadedAt,
    this.addedAfterSubmission = false,
    this.verifiedAt,
    this.rejectedReason,
    this.replacedBy,
  });

  factory fromJson(JsonMap json) => DossierDocument(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? 'autre',
    status: json['status'] as String? ?? 'received',
    title: Json.text(json['title']),
    fileName: Json.text(json['file_name']),
    mimeType: Json.text(json['mime_type']),
    sizeBytes: Json.integer(json['size_bytes']),
    uploadedAt: Json.date(json['uploaded_at']),
    addedAfterSubmission: json['added_after_submission'] == true,
    verifiedAt: Json.date(json['verified_at']),
    rejectedReason: Json.text(json['rejected_reason']),
    replacedBy: json['replaced_by'] as String?,
  );

  /// Identity document kind (refused to partners).
  static const identityKind = 'piece_identite';

  final String id;
  final String kind;
  final String status;
  final String? title;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? uploadedAt;
  final bool addedAfterSubmission;
  final DateTime? verifiedAt;
  final String? rejectedReason;
  final String? replacedBy;

  bool get isIdentity => kind == identityKind;
  bool get isVerified => verifiedAt != null;
  bool get isRejected => status == 'rejected';
  bool get isReplaced => replacedBy != null;

  /// Still waiting for the expert.
  bool get toVerify => !isVerified && !isRejected && !isReplaced;

  @override
  List<Object?> get props => [
    id,
    kind,
    status,
    title,
    fileName,
    mimeType,
    sizeBytes,
    uploadedAt,
    addedAfterSubmission,
    verifiedAt,
    rejectedReason,
    replacedBy,
  ];
}

/// {@template dossier_room}
/// A room of the dossier (V5c).
/// {@endtemplate}
class DossierRoom extends Equatable {
  /// {@macro dossier_room}
  const new({
    required this.id,
    required this.name,
    this.level,
    this.areaM2,
    this.isMain = false,
    this.isAnnex = false,
    this.source,
    this.description,
    this.floorCovering,
    this.glazing,
    this.photosCount = 0,
  });

  factory fromJson(JsonMap json) => DossierRoom(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    level: Json.text(json['level']),
    areaM2: Json.number(json['area_m2']),
    isMain: json['is_main'] == true,
    isAnnex: json['is_annex'] == true,
    source: Json.text(json['source']),
    description: Json.text(json['description']),
    floorCovering: Json.text(json['floor_covering']),
    glazing: Json.text(json['glazing']),
    photosCount: Json.integer(json['photos_count']) ?? 0,
  );

  final String id;
  final String name;
  final String? level;
  final double? areaM2;
  final bool isMain;
  final bool isAnnex;
  final String? source;
  final String? description;
  final String? floorCovering;
  final String? glazing;
  final int photosCount;

  @override
  List<Object?> get props => [
    id,
    name,
    level,
    areaM2,
    isMain,
    isAnnex,
    source,
    description,
    floorCovering,
    glazing,
    photosCount,
  ];
}

/// {@template dossier_photo}
/// A room photo (EPIC-15) with the phone checks and the AI analysis.
/// {@endtemplate}
class DossierPhoto extends Equatable {
  /// {@macro dossier_photo}
  const new({
    required this.id,
    required this.roomId,
    required this.sortOrder,
    this.width,
    this.height,
    this.quality = const {},
    this.analysis,
    this.takenAt,
  });

  factory fromJson(JsonMap json) => DossierPhoto(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    sortOrder: Json.integer(json['sort_order']) ?? 0,
    width: Json.integer(json['width']),
    height: Json.integer(json['height']),
    quality: Json.map(json['quality']) ?? const {},
    analysis: Json.map(json['analysis']),
    takenAt: Json.date(json['taken_at']),
  );

  final String id;
  final String roomId;
  final int sortOrder;
  final int? width;
  final int? height;
  final JsonMap quality;
  final JsonMap? analysis;
  final DateTime? takenAt;

  /// Defects found on the phone (`quality.issues`).
  List<String> get issues => [
    if (quality['issues'] case final List<dynamic> list)
      for (final issue in list)
        if (issue is String) issue,
  ];

  @override
  List<Object?> get props => [
    id,
    roomId,
    sortOrder,
    width,
    height,
    quality,
    analysis,
    takenAt,
  ];
}

/// {@template fill_sheet_row}
/// A line of the fill sheet (EPIC-16 `staff_fill_sheet`).
/// {@endtemplate}
class FillSheetRow extends Equatable {
  /// {@macro fill_sheet_row}
  const new({
    required this.step,
    required this.label,
    this.entityLabel,
    this.value,
    this.source,
    this.quote,
    this.saidAt,
    this.confirmed,
    this.confirmation,
    this.verified,
  });

  factory fromJson(JsonMap json) => FillSheetRow(
    step: json['step'] as String? ?? '',
    label: json['label_fr'] as String? ?? json['field'] as String? ?? '',
    entityLabel: Json.text(json['entity_label']),
    value: Json.text(json['value']),
    source: Json.text(json['source']),
    quote: Json.text(json['quote']),
    saidAt: Json.date(json['said_at']),
    confirmed: json['confirmed'] as bool?,
    confirmation: Json.text(json['confirmation']),
    verified: json['verified'] as bool?,
  );

  final String step;
  final String label;
  final String? entityLabel;
  final String? value;

  /// `dicte`, `dicte_autre_etape`, `saisi`, `extrait`, `externe`,
  /// `non_trace`, `invalide`.
  final String? source;
  final String? quote;
  final DateTime? saidAt;
  final bool? confirmed;
  final String? confirmation;

  /// false: to check (the value does not match what was said).
  final bool? verified;

  @override
  List<Object?> get props => [
    step,
    label,
    entityLabel,
    value,
    source,
    quote,
    saidAt,
    confirmed,
    confirmation,
    verified,
  ];
}

/// {@template voice_turn}
/// A turn of the voice conversation (`staff_voice_thread`).
/// {@endtemplate}
class VoiceTurn extends Equatable {
  /// {@macro voice_turn}
  const new({
    required this.step,
    this.at,
    this.transcript,
    this.reply,
    this.retained = const {},
    this.rejected = const [],
    this.crossStep = const [],
    this.undone = false,
    this.error,
  });

  factory fromJson(JsonMap json) => VoiceTurn(
    step: json['step'] as String? ?? '',
    at: Json.date(json['at']),
    transcript: Json.text(json['transcript']),
    reply: Json.text(json['reply_fr']),
    retained: Json.map(json['retained']) ?? const {},
    rejected: Json.maps(json['rejected']),
    crossStep: Json.maps(json['cross_step']),
    undone: json['undone'] == true,
    error: Json.text(json['error']),
  );

  final String step;
  final DateTime? at;
  final String? transcript;
  final String? reply;
  final JsonMap retained;
  final List<JsonMap> rejected;
  final List<JsonMap> crossStep;
  final bool undone;
  final String? error;

  @override
  List<Object?> get props => [
    step,
    at,
    transcript,
    reply,
    retained,
    rejected,
    crossStep,
    undone,
    error,
  ];
}

/// {@template dossier}
/// A dossier as the back-office sees it (`bo_get_dossier`), shaped by the
/// caller's role.
/// {@endtemplate}
class Dossier extends Equatable {
  /// {@macro dossier}
  const new({
    required this.id,
    required this.role,
    required this.status,
    required this.property,
    this.seller = const {},
    this.owners = const [],
    this.parcels = const [],
    this.previousEstimates = const [],
    this.rooms = const [],
    this.lifestyleItems = const [],
    this.documents = const [],
    this.photos = const [],
    this.voiceSessions = const [],
    this.voiceThread = const [],
    this.fillSheet = const [],
    this.market,
    this.lot,
    this.valuation,
    this.draft,
    this.assignment,
  });

  factory fromJson(JsonMap json) {
    final property = Json.map(json['property']) ?? const {};
    final lot = Json.map(json['lot']);
    final draft = Json.map(json['draft']);
    final assignment = Json.map(json['assignment']);
    return Dossier(
      id: property['id'] as String,
      role: StaffRole.parse(json['role']) ?? StaffRole.partnerExpert,
      status: DossierStatus.parse(property['status']),
      property: property,
      seller: Json.map(json['seller']) ?? const {},
      owners: Json.list(json['owners'], DossierOwner.fromJson),
      parcels: Json.maps(json['parcels']),
      previousEstimates: Json.maps(json['previous_estimates']),
      rooms: Json.list(json['rooms'], DossierRoom.fromJson),
      lifestyleItems: Json.maps(json['lifestyle_items']),
      documents: Json.list(json['documents'], DossierDocument.fromJson),
      photos: Json.list(json['photos'], DossierPhoto.fromJson),
      voiceSessions: Json.maps(json['voice_sessions']),
      voiceThread: Json.list(json['voice_thread'], VoiceTurn.fromJson),
      fillSheet: Json.list(json['fill_sheet'], FillSheetRow.fromJson),
      market: Json.map(json['market']),
      lot: lot == null ? null : LotRef.fromJson(lot),
      valuation: Json.map(json['valuation']),
      draft: draft == null ? null : ValuationDraft.fromJson(draft),
      assignment: assignment == null ? null : StaffRef.fromJson(assignment),
    );
  }

  final String id;

  /// Role of the caller.
  final StaffRole role;
  final DossierStatus status;

  /// The `properties` row (partners: without `owner_id`).
  final JsonMap property;

  /// The seller's account (partners: initials, city, deactivated).
  final JsonMap seller;
  final List<DossierOwner> owners;
  final List<JsonMap> parcels;
  final List<JsonMap> previousEstimates;
  final List<DossierRoom> rooms;
  final List<JsonMap> lifestyleItems;
  final List<DossierDocument> documents;
  final List<DossierPhoto> photos;
  final List<JsonMap> voiceSessions;
  final List<VoiceTurn> voiceThread;
  final List<FillSheetRow> fillSheet;

  /// Latest `market_snapshots` row (EPIC-05).
  final JsonMap? market;
  final LotRef? lot;

  /// Latest certified `valuations` row.
  final JsonMap? valuation;
  final ValuationDraft? draft;
  final StaffRef? assignment;

  String? get propertyType => property['property_type'] as String?;
  String? get city => property['address_city'] as String?;
  double? get livingAreaM2 => Json.number(property['living_area_m2']);
  double? get areaM2 => livingAreaM2 ?? Json.number(property['usable_area_m2']);
  DateTime? get submittedAt => Json.date(property['submitted_at']);
  bool get sellerDeactivated => seller['deactivated'] == true;

  /// Photos of [roomId], in order.
  List<DossierPhoto> photosOf(String roomId) => [
    for (final photo in photos)
      if (photo.roomId == roomId) photo,
  ];

  @override
  List<Object?> get props => [
    id,
    role,
    status,
    property,
    seller,
    owners,
    parcels,
    previousEstimates,
    rooms,
    lifestyleItems,
    documents,
    photos,
    voiceSessions,
    voiceThread,
    fillSheet,
    market,
    lot,
    valuation,
    draft,
    assignment,
  ];
}
