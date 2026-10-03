import 'package:backoffice_repository/src/models/json.dart';
import 'package:equatable/equatable.dart';

/// `valuation_drafts.status`.
enum ValuationDraftStatus {
  editing('editing'),
  submittedForApproval('submitted_for_approval');

  new(this.value);

  final String value;

  static ValuationDraftStatus parse(Object? value) =>
      value == submittedForApproval.value ? submittedForApproval : editing;
}

/// {@template valuation_draft}
/// The valuation being written for a dossier (same keys as
/// `staff_certify_property`).
/// {@endtemplate}
class ValuationDraft extends Equatable {
  /// {@macro valuation_draft}
  const new({
    required this.payload,
    required this.version,
    this.status = ValuationDraftStatus.editing,
    this.updatedAt,
    this.updatedByName,
    this.submittedBy,
    this.submittedByName,
    this.submittedAt,
    this.approvalNote,
  });

  factory fromJson(JsonMap json) => ValuationDraft(
    payload: Json.map(json['payload']) ?? const {},
    version: Json.integer(json['version']) ?? 0,
    status: ValuationDraftStatus.parse(json['status']),
    updatedAt: Json.date(json['updated_at']),
    updatedByName: json['updated_by_name'] as String?,
    submittedBy: json['submitted_by'] as String?,
    submittedByName: json['submitted_by_name'] as String?,
    submittedAt: Json.date(json['submitted_at']),
    approvalNote: Json.text(json['approval_note']),
  );

  final JsonMap payload;

  /// Optimistic lock: 0 before the first save.
  final int version;
  final ValuationDraftStatus status;
  final DateTime? updatedAt;
  final String? updatedByName;
  final String? submittedBy;
  final String? submittedByName;
  final DateTime? submittedAt;

  /// Why an expert sent it back to its author.
  final String? approvalNote;

  @override
  List<Object?> get props => [
    payload,
    version,
    status,
    updatedAt,
    updatedByName,
    submittedBy,
    submittedByName,
    submittedAt,
    approvalNote,
  ];
}
