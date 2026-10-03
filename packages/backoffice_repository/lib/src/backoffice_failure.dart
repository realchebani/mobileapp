import 'dart:convert';

import 'package:backoffice_repository/src/validation/valuation_draft_validator.dart';
import 'package:supabase/supabase.dart';

/// Why a back-office call was refused: the code raised by the `bo_*` SQL
/// functions or returned by `bo-files`, or [unknown].
enum BackOfficeFailureReason {
  notAuthenticated('not_authenticated'),
  notStaff('not_staff'),
  mfaRequired('mfa_required'),
  identityDocumentForbidden('identity_document_forbidden'),
  cannotDeactivateSelf('cannot_deactivate_self'),
  cannotDemoteSelf('cannot_demote_self'),
  forbidden('forbidden'),
  dossierNotFound('dossier_not_found'),
  documentNotFound('document_not_found'),
  ownerNotFound('owner_not_found'),
  memberNotFound('member_not_found'),
  userNotFound('user_not_found'),
  draftNotFound('draft_not_found'),
  fileNotFound('file_not_found'),
  notAssigned('not_assigned'),
  draftConflict('draft_conflict'),
  draftSubmitted('draft_submitted'),
  draftNotSubmitted('draft_not_submitted'),
  draftInvalid('draft_invalid'),
  dossierClosed('dossier_closed'),
  notSubmitted('not_submitted'),
  notCertified('not_certified'),
  noteRequired('note_required'),
  invalidSignatory('invalid_signatory'),
  invalidRole('invalid_role'),
  signatoryNotAllowed('signatory_not_allowed'),
  invalidPath('invalid_path'),
  invalidPages('invalid_pages'),
  originNotAllowed('origin_not_allowed'),
  unauthorized('unauthorized'),
  unknown('');

  new(this.code);

  /// Code in the database exception message or the function answer.
  final String code;

  /// The reason whose code is [message] (exact match), or [unknown].
  static BackOfficeFailureReason parse(String? message) {
    for (final reason in values) {
      if (reason != unknown && reason.code == message) return reason;
    }
    return unknown;
  }
}

/// {@template backoffice_failure}
/// Thrown when a back-office call fails.
/// {@endtemplate}
class BackOfficeFailure implements Exception {
  /// {@macro backoffice_failure}
  const new(this.reason, {this.details, this.errors = const [], this.error});

  /// A failure built from a database, function or network [error].
  factory from(Object error) {
    if (error is BackOfficeFailure) return error;
    if (error is PostgrestException) {
      final reason = BackOfficeFailureReason.parse(error.message);
      final details = error.details?.toString();
      return BackOfficeFailure(
        reason,
        details: details == null || details.isEmpty ? null : details,
        errors: reason == BackOfficeFailureReason.draftInvalid
            ? ValidationError.listFrom(_decode(details))
            : const [],
        error: error,
      );
    }
    if (error is FunctionException) {
      final body = error.details;
      final code = body is Map ? body['error'] as String? : null;
      return BackOfficeFailure(
        BackOfficeFailureReason.parse(code),
        error: error,
      );
    }
    return BackOfficeFailure(BackOfficeFailureReason.unknown, error: error);
  }

  static Object? _decode(String? text) {
    if (text == null) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  final BackOfficeFailureReason reason;

  /// Detail of the database error (name of the other editor of a draft).
  final String? details;

  /// The validation errors of a [BackOfficeFailureReason.draftInvalid].
  final List<ValidationError> errors;

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'BackOfficeFailure($reason, $details, $error)';
}
