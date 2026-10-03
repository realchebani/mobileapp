import 'dart:typed_data';

import 'package:backoffice_repository/src/backoffice_failure.dart';
import 'package:backoffice_repository/src/models/audit_entry.dart';
import 'package:backoffice_repository/src/models/dossier.dart';
import 'package:backoffice_repository/src/models/dossier_summary.dart';
import 'package:backoffice_repository/src/models/json.dart';
import 'package:backoffice_repository/src/models/signed_file.dart';
import 'package:backoffice_repository/src/models/staff.dart';
import 'package:backoffice_repository/src/validation/valuation_draft_validator.dart';
import 'package:supabase/supabase.dart';

/// {@template backoffice_repository}
/// The back-office data access (EPIC-12): every read and write goes through
/// the `bo_*` SQL functions (role, MFA, dossier access and journal checked
/// by the database) and files through the `bo-files` Edge Function.
/// {@endtemplate}
class BackOfficeRepository {
  /// {@macro backoffice_repository}
  const new({required this._client});

  final SupabaseClient _client;

  /// Edge Function signing the file URLs.
  static const filesFunction = 'bo-files';

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(BackOfficeFailure.from(error), stackTrace);
    }
  }

  Future<Object?> _rpc(String name, [Map<String, dynamic>? params]) =>
      _client.rpc<Object?>(name, params: params);

  /// The signed-in user, their role and what the back-office may show.
  Future<StaffMe> me() => _run(
    () async => StaffMe.fromJson(Json.map(await _rpc('bo_me')) ?? const {}),
  );

  /// The queue, oldest sent first.
  Future<List<DossierSummary>> listDossiers({
    List<DossierStatus>? statuses,
    DossierScope scope = DossierScope.all,
    String? search,
    int limit = 100,
    int offset = 0,
  }) => _run(() async {
    final rows = await _rpc('bo_list_dossiers', {
      'p_statuses': statuses?.map((s) => s.value).toList(),
      'p_scope': scope.value,
      'p_search': search,
      'p_limit': limit,
      'p_offset': offset,
    });
    return Json.list(rows, DossierSummary.fromJson);
  });

  /// One dossier (journals its opening).
  Future<Dossier> getDossier(String propertyId) => _run(() async {
    final json = await _rpc('bo_get_dossier', {'p_property_id': propertyId});
    return Dossier.fromJson(Json.map(json) ?? const {});
  });

  /// Admin: gives the dossier to [expertUserId].
  Future<void> assign(String propertyId, String expertUserId, {String? note}) =>
      _run(
        () => _rpc('bo_assign', {
          'p_property_id': propertyId,
          'p_expert_user_id': expertUserId,
          'p_note': note,
        }),
      );

  /// Admin: puts the dossier back in the queue.
  Future<void> unassign(String propertyId) =>
      _run(() => _rpc('bo_unassign', {'p_property_id': propertyId}));

  /// « Prendre en charge »: in review, seller notified.
  Future<void> startReview(String propertyId) =>
      _run(() => _rpc('bo_start_review', {'p_property_id': propertyId}));

  /// Saves the draft at [expectedVersion] (0 the first time); returns the
  /// new version.
  Future<int> saveDraft(
    String propertyId,
    JsonMap payload, {
    required int expectedVersion,
  }) => _run(() async {
    final version = await _rpc('bo_save_draft', {
      'p_property_id': propertyId,
      'p_payload': payload,
      'p_expected_version': expectedVersion,
    });
    return Json.integer(version) ?? expectedVersion + 1;
  });

  /// Errors of the saved draft, as the database sees them.
  Future<List<ValidationError>> validateDraft(String propertyId) => _run(
    () async => ValidationError.listFrom(
      await _rpc('bo_validate_draft', {'p_property_id': propertyId}),
    ),
  );

  /// Partner: hands the draft over for certification.
  Future<void> submitForApproval(String propertyId, {required int version}) =>
      _run(
        () => _rpc('bo_submit_for_approval', {
          'p_property_id': propertyId,
          'p_expected_version': version,
        }),
      );

  /// Expert / admin: sends a submitted draft back with [note].
  Future<void> returnDraft(String propertyId, String note) => _run(
    () =>
        _rpc('bo_return_draft', {'p_property_id': propertyId, 'p_note': note}),
  );

  /// Expert / admin: certifies the draft; returns the valuation id.
  Future<String> certify(String propertyId, {required int version}) =>
      _run(() async {
        final id = await _rpc('bo_certify', {
          'p_property_id': propertyId,
          'p_expected_version': version,
        });
        return '$id';
      });

  /// Short-lived URLs of dossier files (journaled).
  Future<List<SignedFile>> signFiles(
    String propertyId,
    List<FileRequest> files,
  ) => _run(() async {
    final response = await _client.functions.invoke(
      filesFunction,
      body: {
        'action': 'sign_download',
        'property_id': propertyId,
        'items': [for (final file in files) file.toJson()],
      },
    );
    return Json.list(Json.map(response.data)?['files'], SignedFile.fromJson);
  });

  /// Expert / admin: uploads the PDF of the certified valuation and links
  /// it ([pages] shown on V9b).
  Future<void> uploadReport(
    String propertyId,
    Uint8List pdf, {
    required int pages,
  }) => _run(() async {
    final response = await _client.functions.invoke(
      filesFunction,
      body: {'action': 'sign_upload', 'property_id': propertyId},
    );
    final target = Json.map(response.data) ?? const {};
    final bucket = target['bucket'] as String;
    final path = target['path'] as String;
    await _client.storage
        .from(bucket)
        .uploadBinaryToSignedUrl(
          path,
          target['token'] as String,
          pdf,
          const FileOptions(contentType: 'application/pdf'),
        );
    await _rpc('bo_attach_report', {
      'p_property_id': propertyId,
      'p_storage_path': path,
      'p_pages': pages,
    });
  });

  /// Marks a document as checked by the expert.
  Future<void> verifyDocument(String documentId, {bool notify = false}) => _run(
    () => _rpc('bo_verify_document', {
      'p_document_id': documentId,
      'p_notify': notify,
    }),
  );

  /// Refuses a document with [reason] (the seller is notified).
  Future<void> rejectDocument(String documentId, String reason) => _run(
    () => _rpc('bo_reject_document', {
      'p_document_id': documentId,
      'p_reason': reason,
    }),
  );

  /// Expert / admin: identity of a co-owner checked (EPIC-08).
  Future<void> verifyIdentity(String propertyOwnerId) => _run(
    () => _rpc('bo_verify_identity', {'p_property_owner_id': propertyOwnerId}),
  );

  /// Admin: the team.
  Future<List<StaffMember>> listTeam() => _run(
    () async => Json.list(await _rpc('bo_list_team'), StaffMember.fromJson),
  );

  /// Admin: adds or updates a member from the e-mail of an existing user.
  Future<String> upsertMember({
    required String email,
    required StaffRole role,
    required String displayName,
    required String initials,
    String? organisation,
  }) => _run(() async {
    final id = await _rpc('bo_upsert_member', {
      'p_email': email,
      'p_role': role.value,
      'p_display_name': displayName,
      'p_initials': initials,
      'p_organisation': organisation,
    });
    return '$id';
  });

  /// Admin: removes an access at once.
  Future<void> deactivateMember(String userId) =>
      _run(() => _rpc('bo_deactivate_member', {'p_user_id': userId}));

  /// The journal (admin: everything; others: their own actions).
  Future<List<AuditEntry>> audit({
    String? propertyId,
    String? actorUserId,
    String? action,
    DateTime? since,
    DateTime? until,
    int limit = 200,
    int offset = 0,
  }) => _run(() async {
    final rows = await _rpc('bo_audit', {
      'p_property_id': propertyId,
      'p_actor': actorUserId,
      'p_action': action,
      'p_since': since?.toUtc().toIso8601String(),
      'p_until': until?.toUtc().toIso8601String(),
      'p_limit': limit,
      'p_offset': offset,
    });
    return Json.list(rows, AuditEntry.fromJson);
  });
}
