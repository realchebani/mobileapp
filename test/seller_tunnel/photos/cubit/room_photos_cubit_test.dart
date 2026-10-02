import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  late MockPropertyRepository repository;
  late FakePhotoProcessor processor;
  late int ids;

  setUpAll(() {
    registerFallbackValue(testRoomPhoto('fallback'));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    ids = 0;
    repository = MockPropertyRepository();
    processor = FakePhotoProcessor();
    when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
        .thenAnswer((_) async => []);
    when(() => repository.getPhotoUrls(any())).thenAnswer(
      (invocation) async => {
        for (final path in invocation.positionalArguments.single as List)
          path as String: 'https://x/$path',
      },
    );
    when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
        .thenAnswer(
          (invocation) async =>
              invocation.positionalArguments.single as RoomPhoto,
        );
    when(() => repository.analyzeRoomPhoto(any()))
        .thenAnswer((_) async => const RoomPhotoAnalysis(roomKind: 'kitchen'));
    when(() => repository.deleteRoomPhoto(any())).thenAnswer((_) async {});
    when(() => repository.discardRoomPhoto(any())).thenAnswer((_) async {});
    when(() => repository.reorderRoomPhotos(any())).thenAnswer(
      (invocation) async => [
        for (final (i, p)
            in (invocation.positionalArguments.single as List<RoomPhoto>)
                .indexed)
          p.withSortOrder(i),
      ],
    );
  });

  RoomPhotosCubit build({bool analysis = false}) => RoomPhotosCubit(
    repository: repository,
    processor: processor,
    ownerId: 'user-id',
    propertyId: 'property-id',
    roomId: 'r1',
    analysisEnabled: analysis,
    generateId: () => 'p${++ids}',
    now: () => DateTime.utc(2026, 10, 2),
  );

  Future<void> settle() => pumpEventQueue(times: 30);

  group(RoomPhotosCubit, () {
    test('loads the photos of the room and their URLs', () async {
      final photo = testRoomPhoto('a');
      when(() => repository.getRoomPhotos('property-id', roomId: 'r1'))
          .thenAnswer((_) async => [photo]);
      final cubit = build();
      await cubit.load();
      expect(cubit.state.status, RoomPhotosStatus.ready);
      expect(cubit.state.photos, [photo]);
      expect(cubit.state.urls, {
        photo.storagePath: 'https://x/${photo.storagePath}',
      });
      verifyNever(() => repository.analyzeRoomPhoto(any()));
      // Already signed: not asked again.
      await cubit.load();
      verify(() => repository.getPhotoUrls(any())).called(1);
    });

    test('analyses the photos not analysed yet once accepted', () async {
      final done = testRoomPhoto(
        'a',
        analysis: const RoomPhotoAnalysis(roomKind: 'office'),
      );
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [done, testRoomPhoto('b', sortOrder: 1)]);
      final cubit = build(analysis: true);
      await cubit.load();
      await settle();
      verify(() => repository.analyzeRoomPhoto('b')).called(1);
      verifyNever(() => repository.analyzeRoomPhoto('a'));
      expect(cubit.state.photos.last.analysis?.roomKind, 'kitchen');
      expect(cubit.state.analyzing, isEmpty);
    });

    test('a failed load can be retried; failed URLs are tolerated', () async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenThrow(Exception());
      final cubit = build();
      await cubit.load();
      expect(cubit.state.status, RoomPhotosStatus.failure);
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [testRoomPhoto('a')]);
      when(() => repository.getPhotoUrls(any())).thenThrow(Exception());
      await cubit.load();
      expect(cubit.state.status, RoomPhotosStatus.ready);
      expect(cubit.state.urls, isEmpty);
    });

    test('sends the photos of the library one after the other', () async {
      final cubit = build(analysis: true);
      await cubit.load();
      cubit.addFromLibrary([
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ]);
      expect(cubit.state.pending, hasLength(2));
      expect(cubit.state.isSending, isTrue);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect([for (final p in cubit.state.photos) p.id], ['p1', 'p2']);
      final first = cubit.state.photos.first;
      expect(first.storagePath, 'user-id/property-id/photos/r1/p1.jpg');
      expect(first.source, PhotoSource.library);
      expect(first.sortOrder, 0);
      expect(cubit.state.photos.last.sortOrder, 1);
      expect(first.takenAt, DateTime.utc(2026, 10, 2));
      expect(cubit.state.previews.keys, ['p1', 'p2']);
      verify(() => repository.analyzeRoomPhoto('p1')).called(1);
      verify(() => repository.analyzeRoomPhoto('p2')).called(1);
    });

    test('adds a photo of the camera as processed', () async {
      final cubit = build();
      await cubit.load();
      cubit.addFromCamera(processedPhoto([7]));
      await settle();
      expect(cubit.state.photos.single.source, PhotoSource.camera);
      expect(processor.tilts, isEmpty);
      verifyNever(() => repository.analyzeRoomPhoto(any()));
    });

    test('drops the photos beyond 12 with a notice', () async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer(
            (_) async => [for (var i = 0; i < 11; i++) testRoomPhoto('s$i')],
          );
      final cubit = build();
      await cubit.load();
      cubit.addFromLibrary([Uint8List(1), Uint8List(1)]);
      expect(cubit.state.pending, hasLength(1));
      expect(cubit.state.notice, RoomPhotosNotice.limitReached);
      expect(cubit.state.canAdd, isFalse);
      cubit.addFromCamera(processedPhoto());
      expect(cubit.state.noticeCount, 2);
      await settle();
    });

    test('an unreadable photo is dropped with a notice', () async {
      processor = FakePhotoProcessor(error: const FormatException());
      final cubit = build();
      await cubit.load();
      cubit.addFromLibrary([Uint8List(1)]);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.notice, RoomPhotosNotice.unreadable);
    });

    test('a failed upload is kept to retry or discard', () async {
      when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
          .thenThrow(const DocumentUploadFailure('x'));
      final cubit = build();
      await cubit.load();
      cubit
        ..addFromCamera(processedPhoto())
        ..addFromCamera(processedPhoto());
      await settle();
      expect(cubit.state.pending.every((p) => p.failed), isTrue);
      expect(cubit.state.notice, RoomPhotosNotice.uploadFailed);
      expect(cubit.state.isSending, isFalse);
      expect(cubit.state.isBusy, isFalse);

      when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
          .thenAnswer(
            (invocation) async =>
                invocation.positionalArguments.single as RoomPhoto,
          );
      cubit
        ..retry('p1')
        ..retry('p1')
        ..retry('unknown')
        ..discard('p2')
        ..discard('p2');
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.photos.single.id, 'p1');
    });

    test('a lost answer: the photo stored anyway is kept', () async {
      final cubit = build(analysis: true);
      await cubit.load();
      when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
          .thenThrow(TimeoutException('lost'));
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [testRoomPhoto('p1')]);
      cubit.addFromCamera(processedPhoto());
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.photos.single.id, 'p1');
      expect(cubit.state.notice, isNull);
      verify(() => repository.analyzeRoomPhoto('p1')).called(1);
    });

    test('a failed reload after a failed upload keeps it to retry', () async {
      final cubit = build();
      await cubit.load();
      when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
          .thenThrow(Exception());
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenThrow(Exception());
      cubit.addFromCamera(processedPhoto());
      await settle();
      expect(cubit.state.pending.single.failed, isTrue);
      cubit.discard('p1');
      verify(
        () => repository.discardRoomPhoto(
          any(that: isA<RoomPhoto>().having((p) => p.id, 'id', 'p1')),
        ),
      ).called(1);
    });

    test('stops analysing once the consent is withdrawn', () async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [testRoomPhoto('a'), testRoomPhoto('b')]);
      final gate = Completer<RoomPhotoAnalysis>();
      when(() => repository.analyzeRoomPhoto('a'))
          .thenAnswer((_) => gate.future);
      final cubit = build(analysis: true);
      await cubit.load();
      await settle();
      cubit
        ..disableAnalysis()
        ..disableAnalysis();
      expect(cubit.state.analysisEnabled, isFalse);
      expect(cubit.state.analyzing, isEmpty);
      gate.complete(const RoomPhotoAnalysis());
      await settle();
      verifyNever(() => repository.analyzeRoomPhoto('b'));
    });

    test('a pending photo cannot be discarded while it is sent', () async {
      final gate = Completer<void>();
      processor = FakePhotoProcessor(gate: gate);
      final cubit = build();
      await cubit.load();
      cubit
        ..addFromLibrary([Uint8List(1)])
        ..discard('p1');
      expect(cubit.state.pending, hasLength(1));
      gate.complete();
      await settle();
      expect(cubit.state.photos, hasLength(1));
    });

    test('the limit refused by the database drops the photo', () async {
      when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
          .thenThrow(const RoomPhotoLimitFailure('x'));
      final cubit = build();
      await cubit.load();
      cubit.addFromCamera(processedPhoto());
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.notice, RoomPhotosNotice.limitReached);
    });

    test('deletes a photo, or tells it failed', () async {
      final a = testRoomPhoto('a');
      final b = testRoomPhoto('b', sortOrder: 1);
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [a, b]);
      final cubit = build();
      await cubit.load();
      final deleting = cubit.delete(a);
      expect(cubit.state.busyIds, {'a'});
      expect(cubit.state.isBusy, isTrue);
      // Ignored while it is being deleted.
      await cubit.delete(a);
      await deleting;
      expect(cubit.state.photos, [b]);
      expect(cubit.state.busyIds, isEmpty);
      verify(() => repository.deleteRoomPhoto(a)).called(1);

      when(() => repository.deleteRoomPhoto(any())).thenThrow(Exception());
      await cubit.delete(b);
      expect(cubit.state.photos, [b]);
      expect(cubit.state.notice, RoomPhotosNotice.deleteFailed);

      when(() => repository.deleteRoomPhoto(any()))
          .thenThrow(const RoomPhotoRequiredFailure('x'));
      await cubit.delete(b);
      expect(cubit.state.photos, [b]);
      expect(cubit.state.notice, RoomPhotosNotice.lastPhotoRequired);
    });

    test('puts a photo first, or tells it failed', () async {
      final a = testRoomPhoto('a');
      final b = testRoomPhoto('b', sortOrder: 1);
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [a, b]);
      final cubit = build();
      await cubit.load();
      await cubit.moveFirst(a);
      verifyNever(() => repository.reorderRoomPhotos(any()));
      await cubit.moveFirst(b);
      expect([for (final p in cubit.state.photos) p.id], ['b', 'a']);
      expect(cubit.state.photos.first.sortOrder, 0);

      when(() => repository.reorderRoomPhotos(any())).thenThrow(Exception());
      await cubit.moveFirst(cubit.state.photos.last);
      expect([for (final p in cubit.state.photos) p.id], ['b', 'a']);
      expect(cubit.state.notice, RoomPhotosNotice.reorderFailed);
      expect(cubit.state.busyIds, isEmpty);
    });

    test('enables the analysis once, and retries the failed ones', () async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [testRoomPhoto('a')]);
      when(() => repository.analyzeRoomPhoto(any())).thenThrow(Exception());
      final cubit = build();
      await cubit.load();
      cubit
        ..enableAnalysis()
        ..enableAnalysis();
      expect(cubit.state.analysisEnabled, isTrue);
      expect(cubit.state.analyzing, {'a'});
      await settle();
      expect(cubit.state.analysisFailed, {'a'});
      expect(cubit.state.notice, isNull);

      when(
        () => repository.analyzeRoomPhoto(any()),
      ).thenAnswer((_) async => const RoomPhotoAnalysis(peopleVisible: true));
      cubit
        ..retryAnalysis('a')
        ..retryAnalysis('a')
        ..retryAnalysis('unknown');
      await settle();
      expect(cubit.state.analysisFailed, isEmpty);
      expect(cubit.state.photos.single.analysis?.peopleVisible, isTrue);
      verify(() => repository.analyzeRoomPhoto('a')).called(2);
    });

    test('tells when the photo is already being analysed', () async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [testRoomPhoto('a')]);
      when(() => repository.analyzeRoomPhoto(any()))
          .thenThrow(const VisionBusyFailure('x'));
      final cubit = build(analysis: true);
      await cubit.load();
      await settle();
      expect(cubit.state.notice, RoomPhotosNotice.analysisBusy);
      expect(cubit.state.analysisFailed, {'a'});
    });

    test('stops analysing once the quota is used up', () async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [testRoomPhoto('a'), testRoomPhoto('b')]);
      when(() => repository.analyzeRoomPhoto(any()))
          .thenThrow(const VisionQuotaFailure('x'));
      final cubit = build(analysis: true);
      await cubit.load();
      await settle();
      expect(cubit.state.notice, RoomPhotosNotice.analysisQuota);
      expect(cubit.state.analysisFailed, {'a', 'b'});
      verify(() => repository.analyzeRoomPhoto('a')).called(1);
      verifyNever(() => repository.analyzeRoomPhoto('b'));
    });

    test('skips the analysis of a photo deleted meanwhile', () async {
      final a = testRoomPhoto('a');
      final b = testRoomPhoto('b', sortOrder: 1);
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [a, b]);
      final gate = Completer<RoomPhotoAnalysis>();
      when(() => repository.analyzeRoomPhoto('a'))
          .thenAnswer((_) => gate.future);
      final cubit = build(analysis: true);
      await cubit.load();
      await settle();
      await cubit.delete(b);
      gate.complete(const RoomPhotoAnalysis());
      await settle();
      verifyNever(() => repository.analyzeRoomPhoto('b'));
      expect(cubit.state.analyzing, isEmpty);
      expect(cubit.state.analysisFailed, isEmpty);
    });

    test('stops quietly once closed', () async {
      final gate = Completer<void>();
      processor = FakePhotoProcessor(gate: gate);
      final cubit = build(analysis: true);
      await cubit.load();
      cubit.addFromLibrary([Uint8List(1)]);
      await cubit.close();
      gate.complete();
      await settle();
      cubit
        ..addFromCamera(processedPhoto())
        ..enableAnalysis();
      verifyNever(
        () => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')),
      );
    });

    test('PendingPhoto keeps its bytes until processed', () {
      final pending = PendingPhoto(
        id: 'x',
        preview: Uint8List.fromList([1]),
        source: PhotoSource.library,
      );
      final processed = pending.copyWith(processed: processedPhoto([2, 3]));
      expect(processed.preview, [2, 3]);
      expect(processed.copyWith(failed: true).failed, isTrue);
      expect(processed.copyWith(failed: true).processed, isNotNull);
    });
  });
}
