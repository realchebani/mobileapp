import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:property_repository/property_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  const ownerId = 'user-id';
  const propertyId = 'property-id';
  const path = '$ownerId/$propertyId/42_dpe.pdf';
  const documentRow = {
    'id': 'd',
    'property_id': propertyId,
    'kind': 'dpe',
    'storage_path': path,
    'file_name': 'dpe.pdf',
    'mime_type': 'application/pdf',
    'size_bytes': 3,
    'title': 'Mon DPE',
    'owner_ref': null,
    'visibility': ['buyers', 'nope'],
    'added_after_submission': true,
    'verified_at': null,
    'rejected_reason': null,
    'replaced_by': null,
  };

  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late PropertyRepository repository;

  http.Response json(Object? body, {int status = 200}) => http.Response(
    jsonEncode(
      body is List &&
              (current.headers['Accept'] ?? '').contains('vnd.pgrst.object')
          ? body.single
          : body,
    ),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
    request: current,
  );

  http.Response error() =>
      json({'message': 'denied', 'code': '42501'}, status: 400);

  bool isStorage(http.Request request) =>
      request.url.path.startsWith('/storage/');

  setUp(() {
    requests = [];
    client = SupabaseClient(
      'https://project.supabase.co',
      'publishable-key',
      httpClient: MockClient((request) async {
        requests.add(current = request);
        return respond(request);
      }),
    );
    repository = PropertyRepository(
      client: client,
      now: () => DateTime.fromMicrosecondsSinceEpoch(42),
    );
  });

  tearDown(() => client.dispose());

  Matcher failure<T extends PropertyFailure>() =>
      throwsA(isA<T>().having((e) => e.error, 'error', isNotNull));

  test('a document row carries the vault columns', () {
    final document = PropertyDocument.fromJson(documentRow);
    expect(document.kind, DocumentKind.dpe);
    expect(document.title, 'Mon DPE');
    expect(document.visibility, {DocumentVisibility.buyers});
    expect(document.addedAfterSubmission, isTrue);
    expect(document.isVerified, isFalse);
    final verified = PropertyDocument.fromJson(
      Map<String, dynamic>.of(documentRow)..addAll(const {
        'verified_at': '2026-10-03T08:00:00Z',
        'owner_ref': 'o1',
        'rejected_reason': 'Illisible',
        'replaced_by': 'd2',
        'visibility': null,
      }),
    );
    expect(verified.isVerified, isTrue);
    expect(verified.ownerRef, 'o1');
    expect(verified.rejectedReason, 'Illisible');
    expect(verified.replacedBy, 'd2');
    expect(verified.visibility, isEmpty);
    expect(PropertyDocument.fromJson(verified.toJson()), verified);
  });

  test('copies a document', () {
    final document = PropertyDocument.fromJson(documentRow);
    expect(document.withTitle(null).title, isNull);
    expect(document.withTitle('x').visibility, document.visibility);
    expect(
      document.withVisibility(const {DocumentVisibility.notary}).visibility,
      {DocumentVisibility.notary},
    );
    expect(document.replacedWith('d2').replacedBy, 'd2');
    expect(document.replacedWith('d2').title, 'Mon DPE');
  });

  group('getDocumentsOf', () {
    test('lists the documents of several properties', () async {
      respond = (_) => json([documentRow]);
      final documents = await repository.getDocumentsOf(['p1', 'p2']);
      expect(documents.single.id, 'd');
      expect(requests.single.url.queryParameters, {
        'select': '*',
        'property_id': 'in.("p1","p2")',
        'order': 'uploaded_at.asc.nullslast,created_at.asc.nullslast',
      });
    });

    test('returns nothing without properties', () async {
      expect(await repository.getDocumentsOf(const []), isEmpty);
      expect(requests, isEmpty);
    });

    test('throws PropertyLoadFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.getDocumentsOf(['p']),
        failure<PropertyLoadFailure>(),
      );
    });
  });

  test('uploadDocument records the title and the owner', () async {
    respond = (request) => isStorage(request)
        ? json({'Key': 'property-documents/$path'})
        : json([documentRow]);
    await repository.uploadDocument(
      ownerId: ownerId,
      propertyId: propertyId,
      kind: DocumentKind.identityDocument,
      fileName: 'id.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'application/pdf',
      title: 'CNI',
      ownerRef: 'o1',
    );
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body['title'], 'CNI');
    expect(body['owner_ref'], 'o1');
  });

  group('renameDocument', () {
    test('saves the trimmed title', () async {
      respond = (_) => json([documentRow]);
      expect(
        (await repository.renameDocument('d', ' Mon DPE ')).title,
        'Mon DPE',
      );
      expect(jsonDecode(requests.single.body), {'title': 'Mon DPE'});
    });

    test('clears an empty title', () async {
      respond = (_) => json([documentRow]);
      await repository.renameDocument('d', ' ');
      await repository.renameDocument('d', null);
      expect(jsonDecode(requests.first.body), {'title': null});
      expect(jsonDecode(requests.last.body), {'title': null});
    });

    test('throws PropertySaveFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.renameDocument('d', 'x'),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('setDocumentVisibility', () {
    test('calls the function and returns the saved value', () async {
      respond = (_) => json(['buyers', 'notary']);
      expect(
        await repository.setDocumentVisibility('d', const {
          DocumentVisibility.notary,
        }),
        {DocumentVisibility.buyers, DocumentVisibility.notary},
      );
      final request = requests.single;
      expect(request.url.path, '/rest/v1/rpc/set_document_visibility');
      expect(jsonDecode(request.body), {
        'p_document_id': 'd',
        'p_visibility': ['notary'],
      });
    });

    test('throws PropertySaveFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.setDocumentVisibility('d', const {}),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('replaceDocument', () {
    test('calls the function', () async {
      respond = (_) => http.Response('', 204, request: current);
      await repository.replaceDocument(oldId: 'a', newId: 'b');
      expect(requests.single.url.path, '/rest/v1/rpc/replace_document');
      expect(jsonDecode(requests.single.body), {
        'p_old_id': 'a',
        'p_new_id': 'b',
      });
    });

    test('throws PropertySaveFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.replaceDocument(oldId: 'a', newId: 'b'),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('downloadDocument', () {
    test('returns the file', () async {
      respond = (_) => http.Response.bytes([1, 2], 200, request: current);
      expect(await repository.downloadDocument(path), [1, 2]);
      expect(
        requests.single.url.path,
        '/storage/v1/object/property-documents/$path',
      );
    });

    test('throws PropertyLoadFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.downloadDocument(path),
        failure<PropertyLoadFailure>(),
      );
    });
  });
}
