import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';

extension StaffRoleLabel on StaffRole {
  String label(AppLocalizations l10n) => switch (this) {
    StaffRole.admin => l10n.roleAdmin,
    StaffRole.expert => l10n.roleExpert,
    StaffRole.partnerExpert => l10n.rolePartnerExpert,
  };
}

extension DossierStatusLabel on DossierStatus {
  String label(AppLocalizations l10n) => switch (this) {
    DossierStatus.draft => l10n.statusDraft,
    DossierStatus.submitted => l10n.statusSubmitted,
    DossierStatus.inReview => l10n.statusInReview,
    DossierStatus.certified => l10n.statusCertified,
  };
}

/// French label of `properties.property_type`.
String propertyTypeLabel(
  AppLocalizations l10n,
  String? type, [
  String? other,
]) => switch (type) {
  'maison' => l10n.typeMaison,
  'appartement' => l10n.typeAppartement,
  'terrain' => l10n.typeTerrain,
  'stationnement' => l10n.typeStationnement,
  'dependance' => l10n.typeDependance,
  'local_commercial' => l10n.typeLocalCommercial,
  'immeuble' => l10n.typeImmeuble,
  _ => other ?? l10n.typeAutre,
};

/// French message of a failed back-office call.
String failureText(AppLocalizations l10n, Object error) {
  if (error is! BackOfficeFailure) return l10n.failureUnknown;
  return switch (error.reason) {
    BackOfficeFailureReason.forbidden ||
    BackOfficeFailureReason.cannotDeactivateSelf ||
    BackOfficeFailureReason.cannotDemoteSelf => l10n.failureForbidden,
    BackOfficeFailureReason.identityDocumentForbidden =>
      l10n.failureIdentityForbidden,
    BackOfficeFailureReason.dossierNotFound ||
    BackOfficeFailureReason.documentNotFound ||
    BackOfficeFailureReason.ownerNotFound ||
    BackOfficeFailureReason.userNotFound => l10n.teamUserNotFound,
    BackOfficeFailureReason.memberNotFound ||
    BackOfficeFailureReason.draftNotFound ||
    BackOfficeFailureReason.fileNotFound ||
    BackOfficeFailureReason.notAssigned => l10n.failureNotFound,
    BackOfficeFailureReason.draftConflict =>
      error.details == null
          ? l10n.failureConflictAnonymous
          : l10n.failureConflict(error.details!),
    BackOfficeFailureReason.dossierClosed => l10n.failureClosed,
    BackOfficeFailureReason.notSubmitted => l10n.failureNotSubmitted,
    BackOfficeFailureReason.draftSubmitted => l10n.failureDraftSubmitted,
    BackOfficeFailureReason.draftInvalid => l10n.failureDraftInvalid,
    _ => l10n.failureUnknown,
  };
}

/// French label of a `staff_audit_log.action`.
String auditActionLabel(AppLocalizations l10n, String action) =>
    switch (action) {
      'dossier_opened' => l10n.actionDossierOpened,
      'file_signed' => l10n.actionFileSigned,
      'review_started' => l10n.actionReviewStarted,
      'assigned' => l10n.actionAssigned,
      'unassigned' => l10n.actionUnassigned,
      'draft_saved' => l10n.actionDraftSaved,
      'submitted_for_approval' => l10n.actionSubmittedForApproval,
      'draft_returned' => l10n.actionDraftReturned,
      'certified' => l10n.actionCertified,
      'report_upload_signed' => l10n.actionReportUploadSigned,
      'report_attached' => l10n.actionReportAttached,
      'document_verified' => l10n.actionDocumentVerified,
      'document_rejected' => l10n.actionDocumentRejected,
      'identity_verified' => l10n.actionIdentityVerified,
      'member_added' => l10n.actionMemberAdded,
      'member_updated' => l10n.actionMemberUpdated,
      'member_deactivated' => l10n.actionMemberDeactivated,
      _ => action,
    };

/// Who did it: the member's name, or « Éditeur SQL ».
String auditActorLabel(AppLocalizations l10n, AuditEntry entry) =>
    entry.actorRole == 'sql_editor'
    ? l10n.actorSqlEditor
    : entry.actorName ?? entry.actorRole;

/// Short text of a JSON value (journal details, voice values).
String compactJson(Object? value) => switch (value) {
  null => '—',
  final Map<dynamic, dynamic> map =>
    map.entries.map((e) => '${e.key}: ${compactJson(e.value)}').join(', '),
  final List<dynamic> list => list.map(compactJson).join(' ; '),
  _ => '$value',
};
