import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/cubit/surfaces_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _living = Room(
  id: 'r1',
  propertyId: 'p',
  name: 'Séjour',
  level: RoomLevel.groundFloor,
  areaM2: 30,
  isMain: true,
);

const _planned = Room(
  id: 'r2',
  propertyId: 'p',
  name: 'Cuisine',
  areaM2: 12,
  sortOrder: 1,
  source: RoomSource.plan,
);

void main() {
  late MockPropertyRepository repository;

  setUpAll(() => registerFallbackValue(_living));

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.saveRoom(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as Room,
    );
    when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
    when(() => repository.deleteRoomPhotos(any())).thenAnswer((_) async {});
  });

  SurfacesCubit build({List<Room> rooms = const [_living, _planned]}) {
    var next = 0;
    return SurfacesCubit(
      propertyRepository: repository,
      propertyId: 'p',
      rooms: rooms,
      generateId: () => 'new-${next++}',
    );
  }

  group('SurfacesCubit · photos (EPIC-15)', () {
    test('a stored, unchanged room is not written again', () async {
      final cubit = build();
      await cubit.preparePhotos('r1');
      expect(cubit.state.photosRoom, _living);
      verifyNever(() => repository.saveRoom(any()));
      await cubit.preparePhotos('unknown');
      expect(cubit.state.photosRoom, _living);
    });

    test('a new room is written before its photos', () async {
      final cubit = build()
        ..roomAdded(
          const RoomInput(name: 'Bureau', level: null, areaM2: 9, isMain: true),
        );
      final saving = cubit.preparePhotos('new-0');
      expect(cubit.state.savingRoomId, 'new-0');
      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.photosRoom, isNull);
      // Nothing else meanwhile.
      await cubit.preparePhotos('r1');
      await saving;
      final saved = cubit.state.photosRoom;
      expect(saved?.name, 'Bureau');
      expect(saved?.sortOrder, 2);
      expect(cubit.state.savingRoomId, isNull);
      // Recorded: "Continuer" does not write it again.
      await cubit.submit();
      verify(() => repository.saveRoom(any())).called(1);
      expect(cubit.state.submission, SurfacesSubmission.success);
    });

    test('a failed write gives null; submit retries it', () async {
      when(() => repository.saveRoom(any())).thenThrow(Exception());
      final cubit = build()
        ..roomAdded(const RoomInput(name: 'Bureau', level: null, areaM2: 9));
      await cubit.preparePhotos('new-0');
      expect(cubit.state.photosRoom, isNull);
      expect(cubit.state.savingRoomId, isNull);
    });

    test('stops quietly once closed', () async {
      final gate = Completer<Room>();
      when(() => repository.saveRoom(any())).thenAnswer((_) => gate.future);
      final cubit = build()
        ..roomAdded(const RoomInput(name: 'Bureau', level: null, areaM2: 9));
      final saving = cubit.preparePhotos('new-0');
      await cubit.close();
      gate.complete(
        const Room(id: 'new-0', propertyId: 'p', name: 'Bureau', areaM2: 9),
      );
      await saving;
      cubit.photosChanged('r1', 3);

      final failing = Completer<Room>();
      when(() => repository.saveRoom(any())).thenAnswer((_) => failing.future);
      final other = build()
        ..roomAdded(const RoomInput(name: 'Bureau', level: null, areaM2: 9));
      final failed = other.preparePhotos('new-0');
      await other.close();
      failing.completeError(Exception());
      await failed;
    });

    test('records the photo count without writing the room', () async {
      final cubit = build()..photosChanged('r1', 3);
      expect(cubit.state.rooms.first.photosCount, 3);
      expect(cubit.state.photosCount, 3);
      expect(cubit.state.mainRooms, hasLength(1));
      expect(cubit.state.mainRoomsWithoutPhotos, isEmpty);
      await cubit.submit();
      verifyNever(() => repository.saveRoom(any()));
    });

    test('a corrected room of the plan becomes a typed one', () {
      final cubit = build()
        ..roomEdited(
          'r2',
          const RoomInput(name: 'Cuisine', level: null, areaM2: 12),
        );
      expect(cubit.state.rooms.last.source, RoomSource.plan);
      cubit.roomEdited(
        'r2',
        const RoomInput(name: 'Cuisine', level: null, areaM2: 13),
      );
      expect(cubit.state.rooms.last.source, RoomSource.manual);
    });

    test('a removed room loses its photos first', () async {
      final cubit = build()..roomDeleted('r2');
      await cubit.submit();
      verifyInOrder([
        () => repository.deleteRoomPhotos('r2'),
        () => repository.deleteRoom('r2'),
      ]);
    });
  });
}
