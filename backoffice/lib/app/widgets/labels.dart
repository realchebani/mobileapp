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
    BackOfficeFailureReason.memberNotFound ||
    BackOfficeFailureReason.userNotFound ||
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
