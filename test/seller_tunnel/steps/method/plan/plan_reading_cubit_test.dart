import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobileapp/seller_tunnel/steps/method/plan/plan_reading_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _plan = PropertyDocument(
  id: 'plan-doc',
  propertyId: 'property-id',
  kind: DocumentKind.plan,
  storagePath: 'user-id/property-id/1_plan.jpg',
);

void main() {
  late MockPropertyRepository repository;
  late int ids;

  setUpAll(() {
    registerFallbackValue(DocumentKind.plan);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const Room(propertyId: 'p', name: 'x', areaM2: 1));
  });

  setUp(() {
    ids = 0;
    repository = MockPropertyRepository();
    when(
      () => repository.uploadDocument(
        ownerId: any(named: 'ownerId'),
        propertyId: any(named: 'propertyId'),
        kind: any(named: 'kind'),
        fileName: any(named: 'fileName'),
        bytes: any(named: 'bytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async => _plan);
    when(() => repository.readPlan(any()))
        .thenAnswer((_) async => const PlanReading(isFloorPlan: true));
    when(() => repository.saveRoom(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as Room,
    );
  });

  PlanReadingCubit build() => PlanReadingCubit(
    repository: repository,
    property: testProperty,
    encode: (image) async => Uint8List.fromList([...image, 0]),
    generateId: () => 'room-${++ids}',
  );

  group(PlanReadingCubit, () {
    test('stores the plan as a JPEG plan document', () async {
      final cubit = build();
      final stored = cubit.store(Uint8List.fromList([1]));
      expect(cubit.state.status, PlanReadingStatus.uploading);
      expect(cubit.state.isBusy, isTrue);
      // Ignored while busy.
      await cubit.store(Uint8List(1));
      await stored;
      expect(cubit.state.document, _plan);
      expect(cubit.state.status, PlanReadingStatus.idle);
      verify(
        () => repository.uploadDocument(
          ownerId: 'user-id',
          propertyId: 'property-id',
          kind: DocumentKind.plan,
          fileName: 'plan.jpg',
          bytes: Uint8List.fromList([1, 0]),
          mimeType: 'image/jpeg',
        ),
      ).called(1);
    });

    test('a failed upload is told', () async {
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenThrow(Exception());
      final cubit = build();
      await cubit.store(Uint8List(1));
      expect(cubit.state.document, isNull);
      expect(cubit.state.notice, PlanReadingNotice.uploadFailed);
      expect(cubit.state.noticeCount, 1);
    });

    test('reads the plan', () async {
      final cubit = build();
      final reading = cubit.read(_plan);
      expect(cubit.state.status, PlanReadingStatus.reading);
      await cubit.read(_plan);
      await reading;
      expect(cubit.state.reading, const PlanReading(isFloorPlan: true));
      expect(cubit.state.status, PlanReadingStatus.idle);
    });

    test('a failed reading tells the quota apart', () async {
      final cubit = build();
      when(() => repository.readPlan(any()))
          .thenThrow(const VisionQuotaFailure('x'));
      await cubit.read(_plan);
      expect(cubit.state.reading, isNull);
      expect(cubit.state.notice, PlanReadingNotice.quota);
      when(() => repository.readPlan(any())).thenThrow(Exception());
      await cubit.read(_plan);
      expect(cubit.state.notice, PlanReadingNotice.readFailed);
    });

    test('writes the rooms kept after the existing ones', () async {
      final cubit = build();
      final saved = <List<Room>>[];
      const existing = [
        Room(id: 'old', propertyId: 'property-id', name: 'Cave', areaM2: 5),
      ];
      await cubit.saveRooms(
        const [
          PlanRoomInput(
            RoomInput(
              name: 'Séjour',
              level: RoomLevel.groundFloor,
              areaM2: 25,
              isMain: true,
            ),
          ),
          PlanRoomInput(
            RoomInput(name: 'Garage', level: null, areaM2: 15, isAnnex: true),
            fromPlan: false,
          ),
        ],
        existing: existing,
        onRooms: saved.add,
      );
      expect(cubit.state.roomsSaved, isTrue);
      expect(saved, hasLength(2));
      expect(saved.last, [
        existing.single,
        const Room(
          id: 'room-1',
          propertyId: 'property-id',
          name: 'Séjour',
          level: RoomLevel.groundFloor,
          sortOrder: 1,
          areaM2: 25,
          isMain: true,
          source: RoomSource.plan,
        ),
        // Completed by the seller: typed.
        const Room(
          id: 'room-2',
          propertyId: 'property-id',
          name: 'Garage',
          sortOrder: 2,
          areaM2: 15,
          isAnnex: true,
        ),
      ]);
      verifyNever(() => repository.deleteRoom(any()));
    });

    test('replaces the existing rooms and their photos', () async {
      when(() => repository.deleteRoomPhotos(any())).thenAnswer((_) async {});
      when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
      final cubit = build();
      final states = <List<Room>>[];
      const old = Room(
        id: 'old',
        propertyId: 'property-id',
        name: 'Cave',
        areaM2: 5,
      );
      await cubit.saveRooms(
        const [PlanRoomInput(RoomInput(name: 'A', level: null, areaM2: 10))],
        existing: const [old],
        replace: true,
        onRooms: states.add,
      );
      verifyInOrder([
        () => repository.deleteRoomPhotos('old'),
        () => repository.deleteRoom('old'),
      ]);
      expect(states.first, isEmpty);
      expect(states.last.single.sortOrder, 0);
    });

    test('a retry writes the same rows again, never deleting them', () async {
      when(() => repository.deleteRoomPhotos(any())).thenAnswer((_) async {});
      when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
      final cubit = build();
      var calls = 0;
      when(() => repository.saveRoom(any())).thenAnswer((invocation) async {
        if (++calls == 2) throw Exception();
        return invocation.positionalArguments.single as Room;
      });
      const rooms = [
        PlanRoomInput(RoomInput(name: 'A', level: null, areaM2: 10)),
        PlanRoomInput(RoomInput(name: 'B', level: null, areaM2: 10)),
      ];
      var current = <Room>[];
      await cubit.saveRooms(
        rooms,
        existing: const [],
        replace: true,
        onRooms: (rows) => current = rows,
      );
      expect(cubit.state.roomsSaved, isFalse);
      expect(cubit.state.notice, PlanReadingNotice.saveFailed);
      expect([for (final r in current) r.id], ['room-1']);
      await cubit.saveRooms(
        rooms,
        existing: current,
        replace: true,
        onRooms: (rows) => current = rows,
      );
      expect(cubit.state.roomsSaved, isTrue);
      expect([for (final r in current) r.id], ['room-1', 'room-2']);
      verifyNever(() => repository.deleteRoom(any()));
    });

    test('saving is ignored while busy, and stops once closed', () async {
      final gate = Completer<Room>();
      when(() => repository.saveRoom(any())).thenAnswer((_) => gate.future);
      final cubit = build();
      const rooms = [
        PlanRoomInput(RoomInput(name: 'A', level: null, areaM2: 10)),
      ];
      final saving = cubit.saveRooms(
        rooms,
        existing: const [],
        onRooms: (_) {},
      );
      await cubit.saveRooms(rooms, existing: const [], onRooms: (_) {});
      await cubit.close();
      gate.complete(
        const Room(id: 'room-1', propertyId: 'p', name: 'A', areaM2: 10),
      );
      await saving;
      expect(cubit.state.roomsSaved, isFalse);
    });

    test('stops quietly when closed while replacing', () async {
      final gate = Completer<void>();
      when(() => repository.deleteRoomPhotos(any()))
          .thenAnswer((_) => gate.future);
      when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
      final cubit = build();
      final saving = cubit.saveRooms(
        const [PlanRoomInput(RoomInput(name: 'A', level: null, areaM2: 1))],
        existing: const [
          Room(id: 'old', propertyId: 'p', name: 'Cave', areaM2: 5),
        ],
        replace: true,
        onRooms: (_) {},
      );
      await cubit.close();
      gate.complete();
      await saving;
      verifyNever(() => repository.saveRoom(any()));
    });

    test('a failed reading keeps the plan to read again', () async {
      when(() => repository.readPlan(any())).thenThrow(Exception());
      final cubit = build();
      await cubit.read(_plan);
      expect(cubit.state.retryDocument, _plan);
      when(() => repository.readPlan(any()))
          .thenAnswer((_) async => const PlanReading(isFloorPlan: true));
      await cubit.read(_plan);
      expect(cubit.state.retryDocument, isNull);
    });

    test('inputOf takes the kind of the room read', () {
      expect(
        PlanReadingCubit.inputOf(
          const PlanRoom(
            name: 'Chambre 2',
            areaM2: 11,
            level: RoomLevel.firstFloor,
            kind: 'bedroom',
          ),
        ),
        const RoomInput(
          name: 'Chambre 2',
          level: RoomLevel.firstFloor,
          areaM2: 11,
          isMain: true,
        ),
      );
      expect(
        PlanReadingCubit.inputOf(
          const PlanRoom(name: 'Garage', kind: 'garage'),
        ),
        const RoomInput(name: 'Garage', level: null, areaM2: 0, isAnnex: true),
      );
      expect(
        PlanReadingCubit.inputOf(const PlanRoom(name: 'Pièce')).isMain,
        isFalse,
      );
    });
  });

  test('encodePlanImage re-encodes the photo as a JPEG', () async {
    final png = img.encodePng(img.Image(width: 8, height: 4));
    final jpeg = await encodePlanImage(png);
    expect(img.decodeJpg(jpeg)!.width, 8);
  });
}
