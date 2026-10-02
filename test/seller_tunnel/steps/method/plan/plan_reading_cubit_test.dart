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
          RoomInput(
            name: 'Séjour',
            level: RoomLevel.groundFloor,
            areaM2: 25,
            isMain: true,
          ),
          RoomInput(name: 'Garage', level: null, areaM2: 15, isAnnex: true),
        ],
        existing: existing,
        onSaved: saved.add,
      );
      expect(cubit.state.roomsSaved, isTrue);
      expect(saved, hasLength(2));
      expect(saved.last, [
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
        const Room(
          id: 'room-2',
          propertyId: 'property-id',
          name: 'Garage',
          sortOrder: 2,
          areaM2: 15,
          isAnnex: true,
          source: RoomSource.plan,
        ),
      ]);
    });

    test('a retry writes the same rows again', () async {
      final cubit = build();
      var calls = 0;
      when(() => repository.saveRoom(any())).thenAnswer((invocation) async {
        if (++calls == 2) throw Exception();
        return invocation.positionalArguments.single as Room;
      });
      const rooms = [
        RoomInput(name: 'A', level: null, areaM2: 10),
        RoomInput(name: 'B', level: null, areaM2: 10),
      ];
      final first = <Room>[];
      await cubit.saveRooms(
        rooms,
        existing: const [],
        onSaved: (rows) => first
          ..clear()
          ..addAll(rows),
      );
      expect(cubit.state.roomsSaved, isFalse);
      expect(cubit.state.notice, PlanReadingNotice.saveFailed);
      expect([for (final r in first) r.id], ['room-1']);
      final second = <Room>[];
      await cubit.saveRooms(
        rooms,
        existing: const [],
        onSaved: (rows) => second
          ..clear()
          ..addAll(rows),
      );
      expect(cubit.state.roomsSaved, isTrue);
      expect([for (final r in second) r.id], ['room-1', 'room-2']);
    });

    test('saving is ignored while busy, and stops once closed', () async {
      final gate = Completer<Room>();
      when(() => repository.saveRoom(any())).thenAnswer((_) => gate.future);
      final cubit = build();
      const rooms = [RoomInput(name: 'A', level: null, areaM2: 10)];
      final saving = cubit.saveRooms(
        rooms,
        existing: const [],
        onSaved: (_) {},
      );
      await cubit.saveRooms(rooms, existing: const [], onSaved: (_) {});
      await cubit.close();
      gate.complete(
        const Room(id: 'room-1', propertyId: 'p', name: 'A', areaM2: 10),
      );
      await saving;
      expect(cubit.state.roomsSaved, isFalse);
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
