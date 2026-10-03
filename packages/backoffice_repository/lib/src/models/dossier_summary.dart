import 'package:backoffice_repository/src/models/json.dart';
import 'package:backoffice_repository/src/models/staff.dart';
import 'package:backoffice_repository/src/models/valuation_draft.dart';
import 'package:equatable/equatable.dart';

/// Status of a sent dossier (`properties.status`).
enum DossierStatus {
  draft('draft'),
  submitted('submitted'),
  inReview('in_review'),
  certified('certified');

  new(this.value);

  final String value;

  static DossierStatus parse(Object? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return submitted;
  }
}

/// Queue scope (`bo_list_dossiers.p_scope`).
enum DossierScope {
  all('all'),
  mine('mine'),
  unassigned('unassigned');

  new(this.value);

  final String value;
}

/// {@template lot_ref}
/// The sale lot of a dossier (EPIC-13).
/// {@endtemplate}
class LotRef extends Equatable {
  /// {@macro lot_ref}
  const new({
    required this.id,
    required this.name,
    this.saleMode,
    this.mainPropertyId,
    this.members = const [],
  });

  factory fromJson(JsonMap json) => LotRef(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    saleMode: json['sale_mode'] as String?,
    mainPropertyId: json['main_property_id'] as String?,
    members: Json.list(json['members'], LotMember.fromJson),
  );

  final String id;
  final String name;

  /// `ensemble` or `ensemble_ou_separe`.
  final String? saleMode;
  final String? mainPropertyId;
  final List<LotMember> members;

  @override
  List<Object?> get props => [id, name, saleMode, mainPropertyId, members];
}

/// {@template lot_member}
/// A property of a lot, as seen from one of its dossiers.
/// {@endtemplate}
class LotMember extends Equatable {
  /// {@macro lot_member}
  const new({
    required this.id,
    required this.status,
    required this.accessible,
    this.propertyType,
    this.city,
    this.livingAreaM2,
  });

  factory fromJson(JsonMap json) => LotMember(
    id: json['id'] as String,
    status: DossierStatus.parse(json['status']),
    propertyType: json['property_type'] as String?,
    city: json['city'] as String?,
    livingAreaM2: Json.number(json['living_area_m2']),
    accessible: json['accessible'] == true,
  );

  final String id;
  final DossierStatus status;
  final String? propertyType;
  final String? city;
  final double? livingAreaM2;

  /// Whether the caller may open it.
  final bool accessible;

  @override
  List<Object?> get props => [
    id,
    status,
    propertyType,
    city,
    livingAreaM2,
    accessible,
  ];
}

/// {@template dossier_summary}
/// A row of the queue (`bo_list_dossiers`).
/// {@endtemplate}
class DossierSummary extends Equatable {
  /// {@macro dossier_summary}
  const new({
    required this.id,
    required this.status,
    this.propertyType,
    this.propertyTypeOther,
    this.city,
    this.postcode,
    this.livingAreaM2,
    this.usableAreaM2,
    this.submittedAt,
    this.ownerInitials,
    this.ownerDeactivated = false,
    this.lot,
    this.assignedTo,
    this.documentsToVerify = 0,
    this.documentsAddedAfter = 0,
    this.photosCount = 0,
    this.hasVoice = false,
    this.draftStatus,
    this.draftVersion,
  });

  factory fromJson(JsonMap json) {
    final lot = Json.map(json['lot']);
    final assigned = Json.map(json['assigned_to']);
    final draft = Json.map(json['draft']);
    return DossierSummary(
      id: json['id'] as String,
      status: DossierStatus.parse(json['status']),
      propertyType: json['property_type'] as String?,
      propertyTypeOther: Json.text(json['property_type_other']),
      city: json['city'] as String?,
      postcode: json['postcode'] as String?,
      livingAreaM2: Json.number(json['living_area_m2']),
      usableAreaM2: Json.number(json['usable_area_m2']),
      submittedAt: Json.date(json['submitted_at']),
      ownerInitials: json['owner_initials'] as String?,
      ownerDeactivated: json['owner_deactivated'] == true,
      lot: lot == null ? null : LotRef.fromJson(lot),
      assignedTo: assigned == null ? null : StaffRef.fromJson(assigned),
      documentsToVerify: Json.integer(json['documents_to_verify']) ?? 0,
      documentsAddedAfter: Json.integer(json['documents_added_after']) ?? 0,
      photosCount: Json.integer(json['photos_count']) ?? 0,
      hasVoice: json['has_voice'] == true,
      draftStatus: draft == null
          ? null
          : ValuationDraftStatus.parse(draft['status']),
      draftVersion: draft == null ? null : Json.integer(draft['version']),
    );
  }

  final String id;
  final DossierStatus status;
  final String? propertyType;
  final String? propertyTypeOther;
  final String? city;
  final String? postcode;
  final double? livingAreaM2;
  final double? usableAreaM2;
  final DateTime? submittedAt;
  final String? ownerInitials;
  final bool ownerDeactivated;
  final LotRef? lot;
  final StaffRef? assignedTo;
  final int documentsToVerify;
  final int documentsAddedAfter;
  final int photosCount;
  final bool hasVoice;
  final ValuationDraftStatus? draftStatus;
  final int? draftVersion;

  /// Living area, else the usable area (garage, commercial premises).
  double? get areaM2 => livingAreaM2 ?? usableAreaM2;

  @override
  List<Object?> get props => [
    id,
    status,
    propertyType,
    propertyTypeOther,
    city,
    postcode,
    livingAreaM2,
    usableAreaM2,
    submittedAt,
    ownerInitials,
    ownerDeactivated,
    lot,
    assignedTo,
    documentsToVerify,
    documentsAddedAfter,
    photosCount,
    hasVoice,
    draftStatus,
    draftVersion,
  ];
}
