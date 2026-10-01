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
  const propertyRow = {'id': propertyId, 'owner_id': ownerId};
  const property = Property(id: propertyId, ownerId: ownerId);

  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late PropertyRepository repository;

  // Mimics PostgREST: `.single()` asks for one object instead of a list.
  http.Response json(Object body, {int status = 200}) => http.Response(
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
      json({'message': 'permission denied', 'code': '42501'}, status: 401);

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

  group('getOrCreateDossier', () {
    test('returns the latest dossier, whatever its status', () async {
      respond = (_) => json([propertyRow]);

      expect(await repository.getOrCreateDossier(ownerId), property);
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/properties');
      expect(request.url.queryParameters, {
        'select': '*',
        'owner_id': 'eq.$ownerId',
        'order': 'updated_at.desc.nullslast',
        'limit': '1',
      });
    });

    test('creates a draft when there is none', () async {
      respond = (request) =>
          request.method == 'GET' ? json(<Object>[]) : json([propertyRow]);

      expect(await repository.getOrCreateDossier(ownerId), property);
      final insert = requests.last;
      expect(insert.method, 'POST');
      expect(jsonDecode(insert.body), {'owner_id': ownerId});
    });

    test('throws PropertyLoadFailure when reading fails', () async {
      respond = (_) => error();
      await expectLater(
        repository.getOrCreateDossier(ownerId),
        failure<PropertyLoadFailure>(),
      );
    });

    test('returns the draft created concurrently', () async {
      var reads = 0;
      respond = (request) {
        if (request.method == 'POST') {
          return json({
            'message': 'duplicate key value',
            'code': '23505',
          }, status: 409);
        }
        return json(reads++ == 0 ? <Object>[] : [propertyRow]);
      };

      expect(await repository.getOrCreateDossier(ownerId), property);
      expect(requests.map((r) => r.method), ['GET', 'POST', 'GET']);
    });

    test('throws PropertySaveFailure on a conflict without dossier', () async {
      respond = (request) => request.method == 'POST'
          ? json({'message': 'duplicate', 'code': '23505'}, status: 409)
          : json(<Object>[]);
      await expectLater(
        repository.getOrCreateDossier(ownerId),
        failure<PropertySaveFailure>(),
      );
    });

    test('throws PropertySaveFailure on a network error', () async {
      final failing = SupabaseClient(
        'https://project.supabase.co',
        'publishable-key',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') throw http.ClientException('offline');
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(failing.dispose);
      await expectLater(
        PropertyRepository(client: failing).getOrCreateDossier(ownerId),
        failure<PropertySaveFailure>(),
      );
    });

    test('throws PropertySaveFailure when creating fails', () async {
      respond = (request) =>
          request.method == 'GET' ? json(<Object>[]) : error();
      await expectLater(
        repository.getOrCreateDossier(ownerId),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('getProperty', () {
    test('returns the property', () async {
      respond = (_) => json([propertyRow]);
      expect(await repository.getProperty(propertyId), property);
      expect(requests.single.url.queryParameters['id'], 'eq.$propertyId');
    });

    test('throws PropertyNotFoundFailure when there is no row', () async {
      respond = (_) => json(<Object>[]);
      await expectLater(
        repository.getProperty(propertyId),
        throwsA(
          isA<PropertyNotFoundFailure>().having(
            (e) => e.propertyId,
            'propertyId',
            propertyId,
          ),
        ),
      );
    });

    test('throws PropertyLoadFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.getProperty(propertyId),
        failure<PropertyLoadFailure>(),
      );
    });
  });

  group('updateProperty', () {
    test('patches encoded values and returns the property', () async {
      respond = (_) => json([
        {...propertyRow, 'current_step': 2, 'property_type': 'maison'},
      ]);

      final updated = await repository.updateProperty(propertyId, {
        PropertyColumns.currentStep: 2,
        PropertyColumns.propertyType: PropertyType.house,
        PropertyColumns.outdoorEquipment: [OutdoorEquipment.pool],
      });

      expect(updated.currentStep, 2);
      expect(updated.propertyType, PropertyType.house);
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.queryParameters['id'], 'eq.$propertyId');
      expect(jsonDecode(request.body), {
        'current_step': 2,
        'property_type': 'maison',
        'outdoor_equipment': ['piscine'],
      });
    });

    test('throws PropertyNotFoundFailure when nothing was updated', () async {
      respond = (_) => json(<Object>[]);
      await expectLater(
        repository.updateProperty(propertyId, const {}),
        throwsA(isA<PropertyNotFoundFailure>()),
      );
    });

    test('throws PropertySaveFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.updateProperty(propertyId, const {}),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('child collections', () {
    const ownerRow = {
      'id': 'o1',
      'property_id': propertyId,
      'position': 1,
      'first_name': 'Sophie',
      'last_name': 'Durand',
    };
    const parcelRow = {'id': 'pa', 'property_id': propertyId, 'idu': 'x'};
    const estimateRow = {
      'id': 'e',
      'property_id': propertyId,
      'price_eur': 510000,
    };
    const roomRow = {
      'id': 'r',
      'property_id': propertyId,
      'name': 'WC',
      'area_m2': 1.6,
    };
    const itemRow = {
      'id': 'l',
      'property_id': propertyId,
      'kind': 'asset',
      'label': 'École',
    };
    const documentRow = {
      'id': 'd',
      'property_id': propertyId,
      'kind': 'plan',
      'storage_path': '$ownerId/$propertyId/42_plan.pdf',
    };

    final cases =
        <
          String,
          (
            Map<String, Object?>,
            Future<Object?> Function(),
            Future<Object?> Function(),
            Future<void> Function(),
          )
        >{
          'property_owners': (
            ownerRow,
            () => repository.getOwners(propertyId),
            () => repository.saveOwner(PropertyOwner.fromJson(ownerRow)),
            () => repository.deleteOwner('o1'),
          ),
          'property_parcels': (
            parcelRow,
            () => repository.getParcels(propertyId),
            () => repository.saveParcel(PropertyParcel.fromJson(parcelRow)),
            () => repository.deleteParcel('pa'),
          ),
          'previous_estimates': (
            estimateRow,
            () => repository.getPreviousEstimates(propertyId),
            () => repository.savePreviousEstimate(
              PreviousEstimate.fromJson(estimateRow),
            ),
            () => repository.deletePreviousEstimate('e'),
          ),
          'rooms': (
            roomRow,
            () => repository.getRooms(propertyId),
            () => repository.saveRoom(Room.fromJson(roomRow)),
            () => repository.deleteRoom('r'),
          ),
          'lifestyle_items': (
            itemRow,
            () => repository.getLifestyleItems(propertyId),
            () => repository.saveLifestyleItem(LifestyleItem.fromJson(itemRow)),
            () => repository.deleteLifestyleItem('l'),
          ),
        };

    for (final MapEntry(key: table, value: (row, list, save, delete))
        in cases.entries) {
      group(table, () {
        test('lists the rows of the property', () async {
          respond = (_) => json([row]);
          final rows = await list();
          expect(rows, hasLength(1));
          final request = requests.single;
          expect(request.method, 'GET');
          expect(request.url.path, '/rest/v1/$table');
          expect(request.url.queryParameters['property_id'], 'eq.$propertyId');
          expect(request.url.queryParameters['order'], isNotNull);
        });

        test('upserts a row', () async {
          respond = (_) => json([row]);
          await save();
          final request = requests.single;
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/$table');
          expect(
            request.headers['Prefer'],
            contains('resolution=merge-duplicates'),
          );
          expect((jsonDecode(request.body) as Map)['id'], row['id']);
        });

        test('deletes a row', () async {
          respond = (_) => http.Response('', 204, request: current);
          await delete();
          final request = requests.single;
          expect(request.method, 'DELETE');
          expect(request.url.queryParameters['id'], 'eq.${row['id']}');
        });

        test('wraps errors', () async {
          respond = (_) => error();
          await expectLater(list(), failure<PropertyLoadFailure>());
          await expectLater(save(), failure<PropertySaveFailure>());
          await expectLater(delete(), failure<PropertyDeleteFailure>());
        });
      });
    }

    test('getDocuments lists the documents', () async {
      respond = (_) => json([documentRow]);
      expect(await repository.getDocuments(propertyId), [
        PropertyDocument.fromJson(documentRow),
      ]);
      expect(requests.single.url.path, '/rest/v1/property_documents');
    });
  });

  group('documents', () {
    const path = '$ownerId/$propertyId/42_mon_plan_.pdf';
    const documentRow = {
      'id': 'd',
      'property_id': propertyId,
      'kind': 'plan',
      'storage_path': path,
      'file_name': 'mon plan?.pdf',
      'mime_type': 'application/pdf',
      'size_bytes': 3,
    };
    final bytes = Uint8List.fromList([1, 2, 3]);

    Future<PropertyDocument> upload() => repository.uploadDocument(
      ownerId: ownerId,
      propertyId: propertyId,
      kind: DocumentKind.plan,
      fileName: 'mon plan?.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
    );

    bool isStorage(http.Request request) =>
        request.url.path.startsWith('/storage/');

    test('uploadDocument stores the file then records it', () async {
      respond = (request) => isStorage(request)
          ? json({'Key': 'property-documents/$path'})
          : json([documentRow]);

      expect(await upload(), PropertyDocument.fromJson(documentRow));
      final [uploadRequest, insert] = requests;
      expect(uploadRequest.method, 'POST');
      expect(
        uploadRequest.url.path,
        '/storage/v1/object/property-documents/$path',
      );
      expect(insert.url.path, '/rest/v1/property_documents');
      expect(jsonDecode(insert.body), {
        'property_id': propertyId,
        'kind': 'plan',
        'storage_path': path,
        'file_name': 'mon plan?.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 3,
      });
    });

    test('uploadDocument throws DocumentUploadFailure', () async {
      respond = (_) => json({'message': 'too large'}, status: 413);
      await expectLater(upload(), failure<DocumentUploadFailure>());
      expect(requests, hasLength(1));
    });

    test('uploadDocument removes the file when recording fails', () async {
      respond = (request) {
        if (!isStorage(request)) return error();
        return request.method == 'DELETE'
            ? json(<Object>[])
            : json({'Key': 'property-documents/$path'});
      };
      await expectLater(upload(), failure<PropertySaveFailure>());
      final remove = requests.last;
      expect(remove.method, 'DELETE');
      expect(remove.url.path, '/storage/v1/object/property-documents');
      expect(jsonDecode(remove.body), {
        'prefixes': [path],
      });
    });

    test('uploadDocument ignores a failing cleanup', () async {
      respond = (request) {
        if (!isStorage(request) || request.method == 'DELETE') return error();
        return json({'Key': 'property-documents/$path'});
      };
      await expectLater(upload(), failure<PropertySaveFailure>());
    });

    test('updateDocumentKind updates the kind', () async {
      respond = (_) => json([
        {...documentRow, 'kind': 'autre'},
      ]);
      final document = await repository.updateDocumentKind(
        'd',
        DocumentKind.other,
      );
      expect(document.kind, DocumentKind.other);
      expect(jsonDecode(requests.single.body), {'kind': 'autre'});
    });

    test('updateDocumentKind throws PropertySaveFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.updateDocumentKind('d', DocumentKind.other),
        failure<PropertySaveFailure>(),
      );
    });

    test('deleteDocument deletes the row then the file', () async {
      respond = (request) => isStorage(request)
          ? json(<Object>[])
          : http.Response('', 204, request: current);
      await repository.deleteDocument(PropertyDocument.fromJson(documentRow));
      final [row, file] = requests;
      expect(row.method, 'DELETE');
      expect(row.url.path, '/rest/v1/property_documents');
      expect(file.method, 'DELETE');
      expect(jsonDecode(file.body), {
        'prefixes': [path],
      });
    });

    test('deleteDocument throws PropertyDeleteFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.deleteDocument(PropertyDocument.fromJson(documentRow)),
        failure<PropertyDeleteFailure>(),
      );
    });

    test('getDocumentUrl signs a URL', () async {
      respond = (_) => json({'signedURL': '/object/sign/x?token=t'});
      expect(
        await repository.getDocumentUrl(path),
        startsWith('https://project.supabase.co/storage/v1/object/sign/x'),
      );
      final request = requests.single;
      expect(
        request.url.path,
        '/storage/v1/object/sign/property-documents/$path',
      );
      expect(jsonDecode(request.body), containsPair('expiresIn', 600));
    });

    test('getDocumentUrl throws PropertyLoadFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.getDocumentUrl(path),
        failure<PropertyLoadFailure>(),
      );
    });
  });

  test('failures have a readable toString', () {
    expect(
      const PropertyNotFoundFailure('p').toString(),
      'PropertyNotFoundFailure(p)',
    );
    expect(const PropertyLoadFailure().toString(), 'PropertyLoadFailure(null)');
    expect(const PropertySaveFailure(1).toString(), 'PropertySaveFailure(1)');
    expect(
      const PropertyDeleteFailure().toString(),
      'PropertyDeleteFailure(null)',
    );
    expect(
      const DocumentUploadFailure().toString(),
      'DocumentUploadFailure(null)',
    );
  });

  test('defaults the clock', () {
    expect(PropertyRepository(client: client), isNotNull);
  });
}
