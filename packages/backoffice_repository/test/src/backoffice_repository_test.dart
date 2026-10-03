import 'dart:convert';
import 'dart:typed_data';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late BackOfficeRepository repository;

  http.Response json(Object? body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
    request: current,
  );

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  setUp(() {
    requests = [];
    respond = (_) => json(null);
    client = SupabaseClient(
      'https://project.supabase.co',
      'publishable-key',
      httpClient: MockClient((request) async {
        requests.add(current = request);
        return respond(request);
      }),
    );
    repository = BackOfficeRepository(client: client);
  });

  tearDown(() => client.dispose());

  test('me', () async {
    respond = (_) => json({'user_id': 'u1', 'role': 'admin', 'aal2': true});
    final me = await repository.me();
    expect(me.role, StaffRole.admin);
    expect(requests.single.url.path, '/rest/v1/rpc/bo_me');
  });

  test('me without an answer', () async {
    respond = (_) => json({'user_id': 'u1'});
    expect((await repository.me()).isMember, isFalse);
  });

  test('listDossiers sends the filters', () async {
    respond = (_) => json([
      {'id': 'p1', 'status': 'submitted'},
    ]);
    final rows = await repository.listDossiers(
      statuses: [DossierStatus.submitted, DossierStatus.inReview],
      scope: DossierScope.unassigned,
      search: 'Chap',
      limit: 20,
      offset: 40,
    );
    expect(rows.single.id, 'p1');
    expect(bodyOf(requests.single), {
      'p_statuses': ['submitted', 'in_review'],
      'p_scope': 'unassigned',
      'p_search': 'Chap',
      'p_limit': 20,
      'p_offset': 40,
    });
  });

  test('getDossier', () async {
    respond = (_) => json({
      'role': 'expert',
      'property': {'id': 'p1', 'status': 'in_review'},
    });
    final dossier = await repository.getDossier('p1');
    expect(dossier.status, DossierStatus.inReview);
    expect(bodyOf(requests.single), {'p_property_id': 'p1'});
  });

  test('assignment and review calls', () async {
    await repository.assign('p1', 'u1', note: 'Urgent');
    await repository.unassign('p1');
    await repository.startReview('p1');
    expect(requests.map((r) => r.url.path.split('/').last), [
      'bo_assign',
      'bo_unassign',
      'bo_start_review',
    ]);
    expect(bodyOf(requests.first), {
      'p_property_id': 'p1',
      'p_expert_user_id': 'u1',
      'p_note': 'Urgent',
    });
  });

  test('draft calls', () async {
    respond = (request) => switch (request.url.path.split('/').last) {
      'bo_save_draft' => json(4),
      'bo_validate_draft' => json([
        {'path': 'value_eur', 'code': 'required'},
      ]),
      'bo_certify' => json('v1'),
      _ => json(null),
    };
    expect(
      await repository.saveDraft('p1', {'value_eur': 1}, expectedVersion: 3),
      4,
    );
    expect(bodyOf(requests.last), {
      'p_property_id': 'p1',
      'p_payload': {'value_eur': 1},
      'p_expected_version': 3,
    });
    expect(await repository.validateDraft('p1'), [
      const ValidationError('value_eur', 'required'),
    ]);
    await repository.submitForApproval('p1', version: 4);
    expect(bodyOf(requests.last), {
      'p_property_id': 'p1',
      'p_expected_version': 4,
    });
    await repository.returnDraft('p1', 'Revoir');
    expect(bodyOf(requests.last), {'p_property_id': 'p1', 'p_note': 'Revoir'});
    expect(await repository.certify('p1', version: 4), 'v1');
  });

  test('saveDraft without a version in the answer', () async {
    respond = (_) => json(null);
    expect(await repository.saveDraft('p1', {}, expectedVersion: 0), 1);
  });

  test('documents, identity and team', () async {
    respond = (request) => switch (request.url.path.split('/').last) {
      'bo_list_team' => json([
        {'user_id': 'u1', 'role': 'expert'},
      ]),
      'bo_upsert_member' => json('u2'),
      _ => json(null),
    };
    await repository.verifyDocument('d1', notify: true);
    expect(bodyOf(requests.last), {'p_document_id': 'd1', 'p_notify': true});
    await repository.rejectDocument('d1', 'Illisible');
    expect(bodyOf(requests.last), {
      'p_document_id': 'd1',
      'p_reason': 'Illisible',
    });
    await repository.verifyIdentity('o1');
    expect(bodyOf(requests.last), {'p_property_owner_id': 'o1'});
    expect((await repository.listTeam()).single.userId, 'u1');
    expect(
      await repository.upsertMember(
        email: 'a@b.c',
        role: StaffRole.partnerExpert,
        displayName: 'Paul P.',
        initials: 'PP',
        organisation: 'Cabinet',
      ),
      'u2',
    );
    expect(bodyOf(requests.last), {
      'p_email': 'a@b.c',
      'p_role': 'partner_expert',
      'p_display_name': 'Paul P.',
      'p_initials': 'PP',
      'p_organisation': 'Cabinet',
    });
    await repository.deactivateMember('u2');
    expect(bodyOf(requests.last), {'p_user_id': 'u2'});
  });

  test('audit sends the filters in UTC', () async {
    respond = (_) => json([
      {'id': 1, 'action': 'certified'},
    ]);
    final entries = await repository.audit(
      propertyId: 'p1',
      actorUserId: 'u1',
      action: 'certified',
      since: DateTime.utc(2026, 10),
      until: DateTime.utc(2026, 11),
      limit: 10,
      offset: 5,
    );
    expect(entries.single.action, 'certified');
    expect(bodyOf(requests.single), {
      'p_property_id': 'p1',
      'p_actor': 'u1',
      'p_action': 'certified',
      'p_since': '2026-10-01T00:00:00.000Z',
      'p_until': '2026-11-01T00:00:00.000Z',
      'p_limit': 10,
      'p_offset': 5,
    });
  });

  test('signFiles calls bo-files', () async {
    respond = (_) => json({
      'files': [
        {'type': 'photo', 'id': 'ph1', 'url': 'https://signed/ph1'},
      ],
      'expires_in': 300,
    });
    final files = await repository.signFiles('p1', const [
      FileRequest(FileKind.photo, 'ph1'),
    ]);
    expect(files.single.url, 'https://signed/ph1');
    expect(requests.single.url.path, '/functions/v1/bo-files');
    expect(bodyOf(requests.single), {
      'action': 'sign_download',
      'property_id': 'p1',
      'items': [
        {'type': 'photo', 'id': 'ph1'},
      ],
    });
  });

  test('uploadReport signs, uploads, then links the PDF', () async {
    respond = (request) {
      if (request.url.path.startsWith('/functions/')) {
        return json({
          'bucket': 'valuation-reports',
          'path': 'o1/p1/avis.pdf',
          'token': 'tok',
          'signed_url': 'https://upload',
          'valuation_id': 'v1',
        });
      }
      if (request.url.path.startsWith('/storage/')) {
        return json({'Key': 'valuation-reports/o1/p1/avis.pdf'});
      }
      return json(null);
    };
    await repository.uploadReport(
      'p1',
      Uint8List.fromList([37, 80, 68, 70]),
      pages: 11,
    );
    expect(requests, hasLength(3));
    expect(bodyOf(requests.first), {
      'action': 'sign_upload',
      'property_id': 'p1',
    });
    expect(
      requests[1].url.path,
      '/storage/v1/object/upload/sign/valuation-reports/o1/p1/avis.pdf',
    );
    expect(requests[1].url.queryParameters['token'], 'tok');
    expect(bodyOf(requests.last), {
      'p_property_id': 'p1',
      'p_storage_path': 'o1/p1/avis.pdf',
      'p_pages': 11,
    });
  });

  test('errors become BackOfficeFailure', () async {
    respond = (_) => json({
      'message': 'mfa_required',
      'code': '42501',
      'details': null,
    }, status: 403);
    await expectLater(
      repository.listDossiers(),
      throwsA(
        isA<BackOfficeFailure>().having(
          (f) => f.reason,
          'reason',
          BackOfficeFailureReason.mfaRequired,
        ),
      ),
    );
  });
}
