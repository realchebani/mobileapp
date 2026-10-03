import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sale_repository/sale_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  const saleRow = {
    'id': 's1',
    'owner_id': 'o1',
    'property_id': 'p1',
    'formula': 'essentiel',
    'stage': 'plan_chosen',
    'is_test': true,
  };
  const photoRow = {
    'id': 'ph1',
    'sale_id': 's1',
    'storage_path': 'o1/s1/ph1.jpg',
    'sort_order': 0,
  };
  const requestRow = {
    'id': 'r1',
    'sale_id': 's1',
    'kind': 'shooting_photo',
    'status': 'requested',
  };

  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late SaleRepository repository;

  http.Response json(Object? body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
    request: current,
  );

  http.Response dbError(String message, {String? details}) => json({
    'message': message,
    'code': 'P0001',
    'details': details,
  }, status: 400);

  http.Response duplicate() => json({
    'statusCode': '409',
    'error': 'Duplicate',
    'message': 'The resource already exists',
  }, status: 409);

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
    repository = SaleRepository(client: client);
  });

  tearDown(() => client.dispose());

  group('SaleFailure', () {
    test('maps the database codes and the missing items', () {
      final failure = SaleFailure.from(
        const PostgrestException(
          message: 'publish_incomplete',
          details: 'missing_photos,missing_title',
        ),
      );
      expect(failure.reason, SaleFailureReason.publishIncomplete);
      expect(failure.missing, [PublishMissing.title, PublishMissing.photos]);
      expect(failure.toString(), startsWith('SaleFailure('));
      expect(
        SaleFailure.from(const PostgrestException(message: 'boom')).reason,
        SaleFailureReason.unknown,
      );
      expect(SaleFailure.from(Exception()).reason, SaleFailureReason.unknown);
    });
  });

  test('listSales returns the active sales of the owner', () async {
    respond = (_) => json([saleRow]);
    final sales = await repository.listSales('o1');
    expect(sales.single.id, 's1');
    expect(requests.single.url.queryParameters, {
      'select': '*',
      'owner_id': 'eq.o1',
      'stage': 'neq.withdrawn',
      'order': 'created_at.asc.nullslast',
    });
  });

  test('getSale returns the sale or null', () async {
    respond = (_) => json(saleRow);
    expect((await repository.getSale('s1'))?.id, 's1');
    respond = (_) => json(null);
    expect(await repository.getSale('s1'), isNull);
  });

  test('errors become SaleFailure', () async {
    respond = (_) => dbError('lot_sold_together');
    await expectLater(
      repository.chooseFormula(
        saleId: 's1',
        formula: SaleFormula.premium,
        propertyId: 'p1',
      ),
      throwsA(
        isA<SaleFailure>().having(
          (f) => f.reason,
          'reason',
          SaleFailureReason.lotSoldTogether,
        ),
      ),
    );
  });

  test('chooseFormula calls the RPC', () async {
    respond = (_) => json('s1');
    expect(
      await repository.chooseFormula(
        saleId: 's1',
        formula: SaleFormula.premium,
        lotId: 'l1',
      ),
      's1',
    );
    expect(requests.single.url.path, '/rest/v1/rpc/choose_formula');
    expect(jsonDecode(requests.single.body), {
      'p_sale_id': 's1',
      'p_property_id': null,
      'p_lot_id': 'l1',
      'p_formula': 'premium',
    });
  });

  test('updateSale patches and returns the sale', () async {
    respond = (_) => json(saleRow);
    final sale = await repository.updateSale('s1', {'listing_title': 'T'});
    expect(sale.id, 's1');
    expect(requests.single.method, 'PATCH');
    expect(jsonDecode(requests.single.body), {'listing_title': 'T'});
  });

  test('getMandate returns the latest mandate or null', () async {
    respond = (_) => json({
      'id': 'm1',
      'sale_id': 's1',
      'formula': 'essentiel',
      'signed_at': '2026-10-03T08:00:00Z',
    });
    expect((await repository.getMandate('s1'))?.id, 'm1');
    respond = (_) => json(null);
    expect(await repository.getMandate('s1'), isNull);
  });

  group('signTestMandate', () {
    Future<String> sign() => repository.signTestMandate(
      ownerId: 'o1',
      saleId: 's1',
      mandateId: 'm1',
      signaturePng: Uint8List.fromList([1, 2, 3]),
      accepted: true,
      userAgent: 'ios',
      appVersion: '1.0',
    );

    test('uploads the signature then signs', () async {
      respond = (request) => request.url.path.startsWith('/storage')
          ? json({'Key': 'mandate-signatures/o1/s1/m1.png'})
          : json('m1');
      expect(await sign(), 'm1');
      expect(
        requests.first.url.path,
        '/storage/v1/object/mandate-signatures/o1/s1/m1.png',
      );
      expect(requests.last.url.path, '/rest/v1/rpc/sign_test_mandate');
      expect(jsonDecode(requests.last.body), {
        'p_sale_id': 's1',
        'p_mandate_id': 'm1',
        'p_terms_version': 'test-2026-10',
        'p_signature_path': 'o1/s1/m1.png',
        'p_accepted': true,
        'p_user_agent': 'ios',
        'p_app_version': '1.0',
      });
    });

    test('a signature already sent is reused', () async {
      respond = (request) =>
          request.url.path.startsWith('/storage') ? duplicate() : json('m1');
      expect(await sign(), 'm1');
    });

    test('another upload error fails', () async {
      respond = (_) =>
          json({'statusCode': '403', 'message': 'denied'}, status: 403);
      await expectLater(sign(), throwsA(isA<SaleFailure>()));
      expect(requests, hasLength(1));
    });
  });

  test('renderMandate invokes the function', () async {
    respond = (_) => json({'path': 'o1/s1/mandat-m1.pdf', 'sha256': 'x'});
    expect(await repository.renderMandate('m1'), 'o1/s1/mandat-m1.pdf');
    expect(requests.single.url.path, '/functions/v1/render-mandate');
    expect(jsonDecode(requests.single.body), {'mandate_id': 'm1'});
  });

  test('mandateUrl signs the PDF', () async {
    respond = (_) => json({'signedURL': '/object/sign/x?token=t'});
    expect(
      await repository.mandateUrl('o1/s1/m.pdf'),
      startsWith('https://project.supabase.co/storage/v1/object/sign/x'),
    );
    expect(
      requests.single.url.path,
      '/storage/v1/object/sign/sale-documents/o1/s1/m.pdf',
    );
  });

  test('requests: list, ask, cancel', () async {
    respond = (_) => json([requestRow]);
    expect((await repository.getRequests('s1')).single.id, 'r1');
    requests.clear();
    respond = (request) =>
        request.url.path.contains('rpc') ? json(null) : json(requestRow);
    final request = await repository.requestService(
      requestId: 'r1',
      saleId: 's1',
      kind: SaleRequestKind.diagnostics,
      diagnostics: [Diagnostic.dpe],
      preferredSlots: [DateTime.utc(2026, 10, 5, 8)],
    );
    expect(request.id, 'r1');
    expect(jsonDecode(requests.first.body), {
      'p_request_id': 'r1',
      'p_sale_id': 's1',
      'p_kind': 'diagnostics',
      'p_diagnostics': ['dpe'],
      'p_preferred_slots': ['2026-10-05T08:00:00.000Z'],
    });
    requests.clear();
    respond = (_) => json(null);
    await repository.cancelRequest('r1');
    expect(requests.single.url.path, '/rest/v1/rpc/cancel_sale_request');
  });

  test('publish, unpublish, withdraw call their RPCs', () async {
    respond = (_) => json(null);
    await repository.publish('s1');
    await repository.unpublish('s1');
    await repository.withdraw('s1', reason: 'r');
    expect(
      [for (final r in requests) r.url.path],
      [
        '/rest/v1/rpc/publish_listing',
        '/rest/v1/rpc/unpublish_listing',
        '/rest/v1/rpc/withdraw_sale',
      ],
    );
    expect(jsonDecode(requests.last.body), {
      'p_sale_id': 's1',
      'p_reason': 'r',
    });
    respond = (_) =>
        dbError('publish_incomplete', details: 'missing_description');
    await expectLater(
      repository.publish('s1'),
      throwsA(
        isA<SaleFailure>().having((f) => f.missing, 'missing', [
          PublishMissing.description,
        ]),
      ),
    );
  });

  test('getIdentityVerifications reads the owners', () async {
    respond = (_) => json([
      {'id': 'a', 'identity_verified_at': '2026-10-03T08:00:00Z'},
      {'id': 'b', 'identity_verified_at': null},
    ]);
    expect(await repository.getIdentityVerifications('p1'), {
      'a': DateTime.utc(2026, 10, 3, 8),
      'b': null,
    });
  });

  group('listing photos', () {
    const photo = ListingPhoto(
      id: 'ph1',
      saleId: 's1',
      storagePath: 'o1/s1/ph1.jpg',
    );

    test('paths', () {
      expect(
        SaleRepository.listingPhotoPath(
          ownerId: 'o',
          saleId: 's',
          photoId: 'p',
        ),
        'o/s/p.jpg',
      );
      expect(
        SaleRepository.signaturePath(ownerId: 'o', saleId: 's', mandateId: 'm'),
        'o/s/m.png',
      );
    });

    test('getListingPhotos and URLs', () async {
      respond = (_) => json([photoRow]);
      expect((await repository.getListingPhotos('s1')).single, photo);
      respond = (_) => json([
        {'path': 'o1/s1/ph1.jpg', 'signedURL': '/object/sign/a?token=t'},
        {'path': 'gone.jpg', 'error': 'Not found', 'signedURL': null},
      ]);
      final urls = await repository.listingPhotoUrls([
        'o1/s1/ph1.jpg',
        'gone.jpg',
      ]);
      expect(urls.keys, ['o1/s1/ph1.jpg']);
      requests.clear();
      expect(await repository.listingPhotoUrls([]), isEmpty);
      expect(requests, isEmpty);
    });

    test('copyRoomPhoto copies the file then records the row', () async {
      var reads = 0;
      respond = (request) {
        if (request.url.path == '/storage/v1/object/copy') {
          return json({'Key': 'listing-media/o1/s1/ph1.jpg'});
        }
        if (request.method == 'GET') {
          reads++;
          return json(null);
        }
        return json(photoRow);
      };
      expect(
        await repository.copyRoomPhoto(photo, sourcePath: 'o1/p1/photos/r/x'),
        photo,
      );
      expect(reads, 1);
      final copy = requests.firstWhere(
        (r) => r.url.path == '/storage/v1/object/copy',
      );
      expect(jsonDecode(copy.body), {
        'bucketId': 'property-documents',
        'sourceKey': 'o1/p1/photos/r/x',
        'destinationKey': 'o1/s1/ph1.jpg',
        'destinationBucket': 'listing-media',
      });
    });

    test('copyRoomPhoto tolerates a file already copied', () async {
      respond = (request) {
        if (request.url.path == '/storage/v1/object/copy') return duplicate();
        if (request.method == 'GET') return json(null);
        return json(photoRow);
      };
      expect(await repository.copyRoomPhoto(photo, sourcePath: 'x'), photo);
    });

    test('copyRoomPhoto downloads and sends again a refused copy', () async {
      respond = (request) {
        if (request.url.path == '/storage/v1/object/copy') {
          return json({'statusCode': '403', 'message': 'no'}, status: 403);
        }
        if (request.url.path.startsWith(
          '/storage/v1/object/property-documents',
        )) {
          return http.Response.bytes([1, 2], 200, request: current);
        }
        if (request.url.path.startsWith('/storage')) {
          return json({'Key': 'listing-media/o1/s1/ph1.jpg'});
        }
        if (request.method == 'GET') return json(null);
        return json(photoRow);
      };
      expect(await repository.copyRoomPhoto(photo, sourcePath: 'x.jpg'), photo);
      final upload = requests.firstWhere(
        (r) => r.url.path == '/storage/v1/object/listing-media/o1/s1/ph1.jpg',
      );
      expect(upload.method, 'POST');
    });

    test('copyRoomPhoto fails when the download fails too', () async {
      respond = (request) {
        if (request.url.path.startsWith('/storage')) {
          return json({'statusCode': '403', 'message': 'no'}, status: 403);
        }
        return json(null);
      };
      await expectLater(
        repository.copyRoomPhoto(photo, sourcePath: 'x'),
        throwsA(isA<SaleFailure>()),
      );
    });

    test('a row already recorded is returned as is', () async {
      respond = (_) => json(photoRow);
      expect(await repository.copyRoomPhoto(photo, sourcePath: 'x'), photo);
      expect(
        await repository.uploadListingPhoto(
          photo,
          bytes: Uint8List.fromList([1]),
        ),
        photo,
      );
      expect(requests, hasLength(2));
    });

    test('uploadListingPhoto uploads then records', () async {
      respond = (request) {
        if (request.url.path.startsWith('/storage')) {
          return json({'Key': 'listing-media/o1/s1/ph1.jpg'});
        }
        if (request.method == 'GET') return json(null);
        return json(photoRow);
      };
      expect(
        await repository.uploadListingPhoto(
          photo,
          bytes: Uint8List.fromList([1]),
        ),
        photo,
      );
      final upload = requests.firstWhere(
        (r) => r.url.path.startsWith('/storage'),
      );
      expect(upload.url.path, '/storage/v1/object/listing-media/o1/s1/ph1.jpg');
      expect(upload.headers['x-upsert'], 'true');
    });

    test('delete and reorder', () async {
      respond = (_) => json([]);
      await repository.deleteListingPhoto(photo);
      expect(requests.first.method, 'DELETE');
      expect(requests.last.url.path, '/storage/v1/object/listing-media');
      requests.clear();
      respond = (_) => json([photoRow]);
      expect(await repository.reorderListingPhotos('s1', ['ph1']), [photo]);
      expect(jsonDecode(requests.single.body), {
        'p_sale_id': 's1',
        'p_photo_ids': ['ph1'],
      });
    });
  });
}
