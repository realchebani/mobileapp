import 'dart:convert';
import 'dart:math';

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
  const lotRow = {
    'id': 'lot-id',
    'owner_id': ownerId,
    'name': 'Maison + garage',
    'sale_mode': 'ensemble_ou_separe',
  };

  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late PropertyRepository repository;

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

  http.Response error([String message = 'permission denied']) =>
      json({'message': message, 'code': 'P0001'}, status: 400);

  http.Response conflict() =>
      json({'message': 'duplicate key value', 'code': '23505'}, status: 409);

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

  test('generateUuidV4 builds a version 4 UUID', () {
    final pattern = RegExp(
      '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
      r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(generateUuidV4(), matches(pattern));
    expect(generateUuidV4(Random(1)), generateUuidV4(Random(1)));
    expect(generateUuidV4(), isNot(generateUuidV4()));
  });

  group('listProperties', () {
    test('lists the properties of the owner, oldest first', () async {
      respond = (_) => json([propertyRow]);
      expect(await repository.listProperties(ownerId), [property]);
      expect(requests.single.url.queryParameters, {
        'select': '*',
        'owner_id': 'eq.$ownerId',
        'order': 'created_at.asc.nullslast',
      });
    });

    test('throws PropertyLoadFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.listProperties(ownerId),
        failure<PropertyLoadFailure>(),
      );
    });
  });

  group('createProperty', () {
    test('inserts the draft with its id, type and lot', () async {
      respond = (_) => json([
        {...propertyRow, 'property_type': 'stationnement', 'lot_id': 'lot-id'},
      ]);
      final created = await repository.createProperty(
        id: propertyId,
        ownerId: ownerId,
        type: PropertyType.parking,
        lotId: 'lot-id',
      );
      expect(created.propertyType, PropertyType.parking);
      expect(created.lotId, 'lot-id');
      final insert = requests.single;
      expect(insert.method, 'POST');
      expect(jsonDecode(insert.body), {
        'id': propertyId,
        'owner_id': ownerId,
        'property_type': 'stationnement',
        'lot_id': 'lot-id',
      });
    });

    test('sends only the known columns', () async {
      respond = (_) => json([propertyRow]);
      await repository.createProperty(
        id: propertyId,
        ownerId: ownerId,
        type: PropertyType.other,
        typeOther: 'Péniche',
      );
      expect(jsonDecode(requests.single.body), {
        'id': propertyId,
        'owner_id': ownerId,
        'property_type': 'autre',
        'property_type_other': 'Péniche',
      });
    });

    test('returns the property already created by a lost answer', () async {
      respond = (request) =>
          request.method == 'POST' ? conflict() : json([propertyRow]);
      expect(
        await repository.createProperty(id: propertyId, ownerId: ownerId),
        property,
      );
      expect(requests.map((r) => r.method), ['POST', 'GET']);
    });

    test('throws PropertySaveFailure on a conflict with no property', () async {
      respond = (request) =>
          request.method == 'POST' ? conflict() : json(<Object>[]);
      await expectLater(
        repository.createProperty(id: propertyId, ownerId: ownerId),
        failure<PropertySaveFailure>(),
      );
    });

    test('throws PropertyLimitFailure at the limit', () async {
      respond = (_) => error('property_limit_reached');
      await expectLater(
        repository.createProperty(id: propertyId, ownerId: ownerId),
        failure<PropertyLimitFailure>(),
      );
    });

    test('throws LotFrozenFailure when the lot is frozen', () async {
      respond = (_) => error('lot_frozen');
      await expectLater(
        repository.createProperty(
          id: propertyId,
          ownerId: ownerId,
          lotId: 'lot-id',
        ),
        failure<LotFrozenFailure>(),
      );
    });

    test('throws PropertySaveFailure on a network error', () async {
      final failing = SupabaseClient(
        'https://project.supabase.co',
        'publishable-key',
        httpClient: MockClient((_) async => throw http.ClientException('x')),
      );
      addTearDown(failing.dispose);
      await expectLater(
        PropertyRepository(client: failing)
            .createProperty(id: propertyId, ownerId: ownerId),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('deleteProperty', () {
    test('refuses a property that is not a draft', () async {
      await expectLater(
        repository.deleteProperty(
          const Property(
            id: propertyId,
            ownerId: ownerId,
            status: PropertyStatus.submitted,
          ),
        ),
        failure<PropertyDeleteFailure>(),
      );
      expect(requests, isEmpty);
    });

    test('removes the files, then the property', () async {
      respond = (request) {
        if (isStorage(request)) {
          return request.method == 'POST'
              ? json([
                  {'name': 'a.pdf'},
                  {'name': 'b.jpg'},
                ])
              : json(<Object>[]);
        }
        return json([
          {'id': propertyId},
        ]);
      };
      await repository.deleteProperty(property);
      final [list, remove, delete] = requests;
      expect(list.url.path, '/storage/v1/object/list/property-documents');
      expect(
        jsonDecode(list.body),
        containsPair('prefix', 'user-id/$propertyId'),
      );
      expect(jsonDecode(remove.body), {
        'prefixes': ['user-id/$propertyId/a.pdf', 'user-id/$propertyId/b.jpg'],
      });
      expect(delete.method, 'DELETE');
      expect(delete.url.path, '/rest/v1/properties');
      expect(delete.url.queryParameters['id'], 'eq.$propertyId');
    });

    test('skips the removal when there is no file', () async {
      respond = (request) => isStorage(request)
          ? json(<Object>[])
          : json([
              {'id': propertyId},
            ]);
      await repository.deleteProperty(property);
      expect(requests, hasLength(2));
    });

    test('throws PropertyDeleteFailure when nothing was deleted', () async {
      respond = (_) => json(<Object>[]);
      await expectLater(
        repository.deleteProperty(property),
        failure<PropertyDeleteFailure>(),
      );
    });

    test('throws PropertyDeleteFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.deleteProperty(property),
        failure<PropertyDeleteFailure>(),
      );
    });
  });

  group('copyOwners', () {
    const ownerRow = {
      'id': 'o1',
      'property_id': 'from',
      'position': 1,
      'profile_id': ownerId,
      'first_name': 'Marie',
      'last_name': 'Durand',
    };

    test('copies the owners by position', () async {
      respond = (request) => request.method == 'GET'
          ? json([ownerRow])
          : json([
              {...ownerRow, 'id': 'o2', 'property_id': 'to'},
            ]);
      final owners = await repository.copyOwners(
        fromPropertyId: 'from',
        toPropertyId: 'to',
      );
      expect(owners.single.id, 'o2');
      expect(owners.single.propertyId, 'to');
      final upsert = requests.last;
      expect(upsert.method, 'POST');
      expect(upsert.url.queryParameters['on_conflict'], 'property_id,position');
      expect(jsonDecode(upsert.body), [
        {
          'property_id': 'to',
          'position': 1,
          'profile_id': ownerId,
          'first_name': 'Marie',
          'last_name': 'Durand',
          'phone': null,
          'email': null,
        },
      ]);
    });

    test('does nothing without owners', () async {
      respond = (_) => json(<Object>[]);
      expect(
        await repository.copyOwners(fromPropertyId: 'from', toPropertyId: 'to'),
        isEmpty,
      );
      expect(requests, hasLength(1));
    });

    test('throws PropertySaveFailure when the copy fails', () async {
      respond = (request) =>
          request.method == 'GET' ? json([ownerRow]) : error();
      await expectLater(
        repository.copyOwners(fromPropertyId: 'from', toPropertyId: 'to'),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('copyDocument', () {
    const document = PropertyDocument(
      id: 'd',
      propertyId: 'from',
      kind: DocumentKind.identityDocument,
      storagePath: 'user-id/from/1_carte id.jpg',
      fileName: 'carte id.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 12,
    );
    const copyPath = 'user-id/to/42_carte_id.jpg';

    Future<PropertyDocument> copy() =>
        repository.copyDocument(document, ownerId: ownerId, toPropertyId: 'to');

    test('copies the file in the bucket, then records it', () async {
      respond = (request) => isStorage(request)
          ? json({'Key': 'property-documents/$copyPath'})
          : json([
              {
                'id': 'd2',
                'property_id': 'to',
                'kind': 'piece_identite',
                'storage_path': copyPath,
              },
            ]);
      final copied = await copy();
      expect(copied.storagePath, copyPath);
      final [file, insert] = requests;
      expect(file.url.path, '/storage/v1/object/copy');
      expect(jsonDecode(file.body), {
        'bucketId': 'property-documents',
        'sourceKey': document.storagePath,
        'destinationKey': copyPath,
      });
      expect(jsonDecode(insert.body), {
        'property_id': 'to',
        'kind': 'piece_identite',
        'storage_path': copyPath,
        'file_name': 'carte id.jpg',
        'mime_type': 'image/jpeg',
        'size_bytes': 12,
      });
    });

    test('names the copy after the path without a file name', () async {
      respond = (request) => isStorage(request)
          ? json({'Key': 'x'})
          : json([
              {
                'id': 'd2',
                'property_id': 'to',
                'kind': 'piece_identite',
                'storage_path': 'user-id/to/42_scan.pdf',
              },
            ]);
      await repository.copyDocument(
        const PropertyDocument(
          id: 'd',
          propertyId: 'from',
          kind: DocumentKind.identityDocument,
          storagePath: 'user-id/from/scan.pdf',
        ),
        ownerId: ownerId,
        toPropertyId: 'to',
      );
      expect(
        jsonDecode(requests.first.body),
        containsPair('destinationKey', 'user-id/to/42_scan.pdf'),
      );
    });

    test('throws DocumentUploadFailure when the copy fails', () async {
      respond = (_) => json({'message': 'denied'}, status: 403);
      await expectLater(copy(), failure<DocumentUploadFailure>());
      expect(requests, hasLength(1));
    });

    test('removes the copy when recording fails', () async {
      respond = (request) {
        if (!isStorage(request)) return error();
        return request.method == 'DELETE'
            ? json(<Object>[])
            : json({'Key': 'x'});
      };
      await expectLater(copy(), failure<PropertySaveFailure>());
      expect(jsonDecode(requests.last.body), {
        'prefixes': [copyPath],
      });
    });

    test('ignores a failing cleanup', () async {
      respond = (request) {
        if (!isStorage(request) || request.method == 'DELETE') return error();
        return json({'Key': 'x'});
      };
      await expectLater(copy(), failure<PropertySaveFailure>());
    });
  });

  group('lots', () {
    const lot = PropertyLot(
      id: 'lot-id',
      ownerId: ownerId,
      name: 'Maison + garage',
      saleMode: LotSaleMode.togetherOrSeparately,
    );

    test('listLots lists the lots of the owner', () async {
      respond = (_) => json([lotRow]);
      expect(await repository.listLots(ownerId), [lot]);
      expect(requests.single.url.path, '/rest/v1/property_lots');
      expect(requests.single.url.queryParameters['owner_id'], 'eq.$ownerId');
    });

    test('listLots throws PropertyLoadFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.listLots(ownerId),
        failure<PropertyLoadFailure>(),
      );
    });

    test('createLot inserts the lot', () async {
      respond = (_) => json([lotRow]);
      expect(
        await repository.createLot(
          id: 'lot-id',
          ownerId: ownerId,
          name: 'Maison + garage',
          saleMode: LotSaleMode.togetherOrSeparately,
        ),
        lot,
      );
      expect(jsonDecode(requests.single.body), {
        'id': 'lot-id',
        'owner_id': ownerId,
        'name': 'Maison + garage',
        'sale_mode': 'ensemble_ou_separe',
      });
    });

    test('createLot returns the lot created by a lost answer', () async {
      respond = (request) =>
          request.method == 'POST' ? conflict() : json([lotRow]);
      expect(await repository.createLot(id: 'lot-id', ownerId: ownerId), lot);
    });

    test('createLot fails on a conflict with no lot', () async {
      respond = (request) =>
          request.method == 'POST' ? conflict() : json(<Object>[]);
      await expectLater(
        repository.createLot(id: 'lot-id', ownerId: ownerId),
        failure<PropertySaveFailure>(),
      );
    });

    test('createLot fails when the lookup fails', () async {
      respond = (request) => request.method == 'POST' ? conflict() : error();
      await expectLater(
        repository.createLot(id: 'lot-id', ownerId: ownerId),
        failure<PropertySaveFailure>(),
      );
    });

    test('createLot throws PropertySaveFailure on a network error', () async {
      final failing = SupabaseClient(
        'https://project.supabase.co',
        'publishable-key',
        httpClient: MockClient((_) async => throw http.ClientException('x')),
      );
      addTearDown(failing.dispose);
      await expectLater(
        PropertyRepository(client: failing)
            .createLot(id: 'lot-id', ownerId: ownerId),
        failure<PropertySaveFailure>(),
      );
    });

    test('updateLot patches the lot', () async {
      respond = (_) => json([
        {...lotRow, 'sale_mode': 'ensemble'},
      ]);
      final updated = await repository.updateLot('lot-id', {
        PropertyLotColumns.saleMode: LotSaleMode.together,
      });
      expect(updated.saleMode, LotSaleMode.together);
      expect(jsonDecode(requests.single.body), {'sale_mode': 'ensemble'});
    });

    test('updateLot throws LotFrozenFailure when nothing changed', () async {
      respond = (_) => json(<Object>[]);
      await expectLater(
        repository.updateLot('lot-id', {PropertyLotColumns.name: 'x'}),
        throwsA(isA<LotFrozenFailure>()),
      );
    });

    test('updateLot throws PropertySaveFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.updateLot('lot-id', {PropertyLotColumns.name: 'x'}),
        failure<PropertySaveFailure>(),
      );
    });

    test('deleteLot deletes the lot', () async {
      respond = (_) => json([
        {'id': 'lot-id'},
      ]);
      await repository.deleteLot('lot-id');
      expect(requests.single.method, 'DELETE');
    });

    test('deleteLot throws LotFrozenFailure when not deleted', () async {
      respond = (_) => json(<Object>[]);
      await expectLater(
        repository.deleteLot('lot-id'),
        throwsA(isA<LotFrozenFailure>()),
      );
    });

    test('deleteLot throws PropertyDeleteFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.deleteLot('lot-id'),
        failure<PropertyDeleteFailure>(),
      );
    });

    test('setPropertyLot sets the lot of the property', () async {
      respond = (_) => json([
        {...propertyRow, 'lot_id': 'lot-id'},
      ]);
      final updated = await repository.setPropertyLot(propertyId, 'lot-id');
      expect(updated.lotId, 'lot-id');
      expect(jsonDecode(requests.single.body), {'lot_id': 'lot-id'});
    });

    test('setPropertyLot throws LotFrozenFailure for a frozen lot', () async {
      respond = (_) => error('lot_frozen');
      await expectLater(
        repository.setPropertyLot(propertyId, null),
        failure<LotFrozenFailure>(),
      );
    });
  });
}
