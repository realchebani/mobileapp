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
  const roomId = 'room-id';
  const photoId = 'photo-id';
  const path = '$ownerId/$propertyId/photos/$roomId/$photoId.jpg';
  const photoRow = {
    'id': photoId,
    'property_id': propertyId,
    'room_id': roomId,
    'storage_path': path,
    'width': 2048,
    'height': 1536,
    'size_bytes': 3,
    'sort_order': 1,
    'source': 'library',
    'quality': {
      'brightness': 40.5,
      'sharpness': 12,
      'tilt_deg': null,
      'issues': ['dark', 'blurry', 'nope'],
    },
    'analysis': {
      'version': 1,
      'room_kind': 'kitchen',
      'floor_covering': 'carrelage',
      'glazing': 'double',
      'condition_notes': ['Fissure au plafond', 3],
      'personal_items': ['Courrier'],
      'people_visible': true,
      'quality_issues': ['dark'],
      'model': 'm/x',
    },
    'taken_at': '2026-10-02T10:00:00.000Z',
  };
  final photo = RoomPhoto.fromJson(photoRow);
  final bytes = Uint8List.fromList([1, 2, 3]);

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

  http.Response error({String message = 'denied', String code = '42501'}) =>
      json({'message': message, 'code': code}, status: 400);

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
    repository = PropertyRepository(client: client);
  });

  tearDown(() => client.dispose());

  Matcher failure<T extends PropertyFailure>() =>
      throwsA(isA<T>().having((e) => e.error, 'error', isNotNull));

  group('models', () {
    test('parse a photo row', () {
      expect(
        photo.quality,
        const PhotoQuality(
          brightness: 40.5,
          sharpness: 12,
          issues: [PhotoQualityIssue.dark, PhotoQualityIssue.blurry],
        ),
      );
      expect(photo.analysis!.conditionNotes, ['Fissure au plafond']);
      expect(photo.analysis!.glazing, Glazing.double);
      expect(photo.analysis!.peopleVisible, isTrue);
      expect(photo.source, PhotoSource.library);
      expect(photo.takenAt, DateTime.utc(2026, 10, 2, 10));
    });

    test('default the optional columns', () {
      final bare = RoomPhoto.fromJson(const {
        'id': photoId,
        'property_id': propertyId,
        'room_id': roomId,
        'storage_path': path,
      });
      expect(bare.sortOrder, 0);
      expect(bare.source, PhotoSource.camera);
      expect(bare.quality, isNull);
      expect(bare.analysis, isNull);
      const empty = RoomPhotoAnalysis();
      expect(RoomPhotoAnalysis.fromJson(const {}), empty);
    });

    test('copy with an analysis or an order', () {
      const analysis = RoomPhotoAnalysis(roomKind: 'office');
      expect(photo.withAnalysis(analysis).analysis, analysis);
      expect(photo.withSortOrder(5).sortOrder, 5);
      expect(photo.withSortOrder(5).analysis, photo.analysis);
    });

    test('insert JSON leaves the analysis out', () {
      expect(photo.toInsertJson(), {
        'id': photoId,
        'property_id': propertyId,
        'room_id': roomId,
        'storage_path': path,
        'width': 2048,
        'height': 1536,
        'size_bytes': 3,
        'sort_order': 1,
        'source': 'library',
        'quality': {
          'brightness': 40.5,
          'sharpness': 12.0,
          'tilt_deg': null,
          'issues': ['dark', 'blurry'],
        },
        'taken_at': '2026-10-02T10:00:00.000Z',
      });
    });

    test('parse a plan reading', () {
      final reading = PlanReading.fromJson(const {
        'is_floor_plan': true,
        'rooms': [
          {'name': 'Séjour', 'area_m2': 25.4, 'level': 'rdc', 'kind': 'x'},
          {'name': 'WC', 'area_m2': null, 'level': null, 'kind': null},
          'garbage',
        ],
        'printed_total_m2': 30,
        'rooms_total_m2': 25.4,
        'total_matches': false,
      });
      expect(reading.rooms, const [
        PlanRoom(
          name: 'Séjour',
          areaM2: 25.4,
          level: RoomLevel.groundFloor,
          kind: 'x',
        ),
        PlanRoom(name: 'WC'),
      ]);
      expect(reading.printedTotalM2, 30);
      expect(reading.totalMatches, isFalse);
      expect(
        PlanReading.fromJson(const {}),
        const PlanReading(isFloorPlan: false),
      );
    });
  });

  test('roomPhotoPath builds the photos folder path', () {
    expect(
      PropertyRepository.roomPhotoPath(
        ownerId: ownerId,
        propertyId: propertyId,
        roomId: roomId,
        photoId: photoId,
      ),
      path,
    );
  });

  group('getRoomPhotos', () {
    test('lists the photos of a property, or of a room', () async {
      respond = (_) => json([photoRow]);
      expect(await repository.getRoomPhotos(propertyId), [photo]);
      await repository.getRoomPhotos(propertyId, roomId: roomId);
      final [all, room] = requests;
      expect(all.url.queryParameters['property_id'], 'eq.$propertyId');
      expect(all.url.queryParameters.containsKey('room_id'), isFalse);
      expect(room.url.queryParameters['room_id'], 'eq.$roomId');
    });

    test('throws PropertyLoadFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.getRoomPhotos(propertyId),
        failure<PropertyLoadFailure>(),
      );
    });
  });

  group('uploadRoomPhoto', () {
    test('uploads the file (overwriting) then records it', () async {
      respond = (request) =>
          isStorage(request) ? json({'Key': path}) : json([photoRow]);
      expect(await repository.uploadRoomPhoto(photo, bytes: bytes), photo);
      final [upload, insert] = requests;
      expect(upload.url.path, '/storage/v1/object/property-documents/$path');
      expect(upload.headers['x-upsert'], 'true');
      expect(insert.url.path, '/rest/v1/room_photos');
      expect(jsonDecode(insert.body), photo.toInsertJson());
    });

    test('throws DocumentUploadFailure when the upload fails', () async {
      respond = (_) => json({'message': 'too large'}, status: 413);
      await expectLater(
        repository.uploadRoomPhoto(photo, bytes: bytes),
        failure<DocumentUploadFailure>(),
      );
    });

    test('returns the row recorded by an earlier try', () async {
      respond = (request) {
        if (isStorage(request)) return json({'Key': path});
        if (request.method == 'POST') {
          return error(message: 'duplicate', code: '23505');
        }
        return json([photoRow]);
      };
      expect(await repository.uploadRoomPhoto(photo, bytes: bytes), photo);
      expect(requests.where(isStorage), hasLength(1));
    });

    test('maps the limit and removes the file', () async {
      respond = (request) {
        if (isStorage(request)) return json({'Key': path});
        return error(message: 'room_photo_limit_reached', code: 'P0001');
      };
      await expectLater(
        repository.uploadRoomPhoto(photo, bytes: bytes),
        failure<RoomPhotoLimitFailure>(),
      );
      expect(requests.last.method, 'DELETE');
    });

    test('throws PropertySaveFailure when a duplicate is not found', () async {
      var reads = 0;
      respond = (request) {
        if (isStorage(request)) {
          return request.method == 'DELETE' ? error() : json({'Key': path});
        }
        if (request.method == 'POST') {
          return error(message: 'duplicate', code: '23505');
        }
        return reads++ == 0 ? json(<Object>[]) : error();
      };
      await expectLater(
        repository.uploadRoomPhoto(photo, bytes: bytes),
        failure<PropertySaveFailure>(),
      );
      await expectLater(
        repository.uploadRoomPhoto(photo, bytes: bytes),
        failure<PropertySaveFailure>(),
      );
    });
  });

  test('uploadRoomPhoto keeps the file when the answer is lost', () async {
    respond = (request) {
      if (isStorage(request)) return json({'Key': path});
      throw http.ClientException('connection reset');
    };
    await expectLater(
      repository.uploadRoomPhoto(photo, bytes: bytes),
      failure<PropertySaveFailure>(),
    );
    expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  group('discardRoomPhoto', () {
    test('deletes the row by id and the file', () async {
      respond = (request) => json(<Object>[]);
      await repository.discardRoomPhoto(photo);
      final [row, file] = requests;
      expect(row.url.queryParameters['id'], 'eq.$photoId');
      expect(jsonDecode(file.body), {
        'prefixes': [path],
      });
    });

    test('never throws', () async {
      respond = (_) => error();
      await repository.discardRoomPhoto(photo);
      expect(requests, hasLength(2));
    });
  });

  group('deleteRoomPhoto', () {
    test('deletes the row then the file', () async {
      respond = (request) => isStorage(request)
          ? json(<Object>[])
          : json([
              {'id': photoId},
            ]);
      await repository.deleteRoomPhoto(photo);
      final [row, file] = requests;
      expect(row.url.path, '/rest/v1/room_photos');
      expect(jsonDecode(file.body), {
        'prefixes': [path],
      });
    });

    test('keeps the file of a locked dossier', () async {
      respond = (_) => json(<Object>[]);
      await repository.deleteRoomPhoto(photo);
      expect(requests, hasLength(1));
    });

    test('throws PropertyDeleteFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.deleteRoomPhoto(photo),
        failure<PropertyDeleteFailure>(),
      );
    });
  });

  group('deleteRoomPhotos', () {
    test('deletes the rows of the room, then their files', () async {
      respond = (request) => isStorage(request)
          ? json(<Object>[])
          : json([
              {'storage_path': path},
            ]);
      await repository.deleteRoomPhotos(roomId);
      final [rows, files] = requests;
      expect(rows.url.queryParameters['room_id'], 'eq.$roomId');
      expect(jsonDecode(files.body), {
        'prefixes': [path],
      });
    });

    test('does nothing more without photos', () async {
      respond = (_) => json(<Object>[]);
      await repository.deleteRoomPhotos(roomId);
      expect(requests, hasLength(1));
    });

    test('throws PropertyDeleteFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.deleteRoomPhotos(roomId),
        failure<PropertyDeleteFailure>(),
      );
    });
  });

  group('reorderRoomPhotos', () {
    test('writes only the photos whose order changes', () async {
      final first = photo.withSortOrder(0);
      final moved = RoomPhoto.fromJson(Map.of(photoRow)..['id'] = 'b');
      respond = (_) => json([
        {...photoRow, 'id': 'b', 'sort_order': 1},
      ]);
      // `moved` is at sort_order 1 already: nothing to write.
      expect(await repository.reorderRoomPhotos([first, moved]), [
        first,
        moved,
      ]);
      expect(requests, isEmpty);
      final reordered = await repository.reorderRoomPhotos([moved, first]);
      expect(requests, hasLength(2));
      expect(jsonDecode(requests.first.body), {'sort_order': 0});
      expect(reordered, hasLength(2));
    });

    test('throws PropertySaveFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.reorderRoomPhotos([photo]),
        failure<PropertySaveFailure>(),
      );
    });
  });

  group('getPhotoUrls', () {
    test('signs the paths and leaves the missing ones out', () async {
      respond = (_) => json([
        {'path': path, 'signedURL': '/object/sign/a?token=t'},
        {'path': 'gone.jpg', 'error': 'Not found', 'signedURL': null},
      ]);
      final urls = await repository.getPhotoUrls([path, 'gone.jpg']);
      expect(urls.keys, [path]);
      expect(urls[path], startsWith('https://project.supabase.co/storage/v1'));
      expect(jsonDecode(requests.single.body), {
        'expiresIn': 3600,
        'paths': [path, 'gone.jpg'],
      });
    });

    test('asks nothing without paths', () async {
      expect(await repository.getPhotoUrls(const []), isEmpty);
      expect(requests, isEmpty);
    });

    test('throws PropertyLoadFailure', () async {
      respond = (_) => error();
      await expectLater(
        repository.getPhotoUrls([path]),
        failure<PropertyLoadFailure>(),
      );
    });
  });

  group('vision', () {
    test('analyzeRoomPhoto invokes vision-room', () async {
      respond = (_) =>
          json({'analysis': photoRow['analysis']!, 'cached': false});
      final analysis = await repository.analyzeRoomPhoto(photoId);
      expect(analysis.roomKind, 'kitchen');
      final request = requests.single;
      expect(request.url.path, '/functions/v1/vision-room');
      expect(jsonDecode(request.body), {
        'photo_id': photoId,
        'consent': 'photo_analysis_v1',
      });
    });

    test('readPlan invokes plan-reader', () async {
      respond = (_) => json({
        'reading': {'is_floor_plan': true, 'rooms': <Object>[]},
        'cached': true,
      });
      final reading = await repository.readPlan('doc');
      expect(reading.isFloorPlan, isTrue);
      expect(requests.single.url.path, '/functions/v1/plan-reader');
      expect(jsonDecode(requests.single.body), {
        'document_id': 'doc',
        'consent': 'photo_analysis_v1',
      });
    });

    test('maps the quota and the other errors', () async {
      respond = (_) => json({'error': 'quota'}, status: 429);
      await expectLater(
        repository.analyzeRoomPhoto(photoId),
        failure<VisionQuotaFailure>(),
      );
      respond = (_) => json({'error': 'upstream'}, status: 502);
      await expectLater(
        repository.readPlan('doc'),
        failure<VisionRequestFailure>(),
      );
    });

    test('failures have a readable toString', () {
      expect(
        const RoomPhotoLimitFailure('x').toString(),
        'RoomPhotoLimitFailure(x)',
      );
      expect(const VisionQuotaFailure('x').toString(), 'VisionQuotaFailure(x)');
      expect(
        const VisionRequestFailure('x').toString(),
        'VisionRequestFailure(x)',
      );
    });
  });
}
