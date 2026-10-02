import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
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
  areaM2: 38.5,
  floorCovering: 'parquet_chene',
  isMain: true,
  ceilingHeightM: 2.5,
  photosCount: 4,
  source: RoomSource.scan,
);

const _kitchen = Room(
  id: 'r2',
  propertyId: 'p',
  name: 'Cuisine',
  level: RoomLevel.groundFloor,
  areaM2: 12.8,
  sortOrder: 1,
);

const _bedroom = RoomInput(
  name: 'Chambre 1',
  level: RoomLevel.firstFloor,
  areaM2: 12.345,
  isMain: true,
);

List<List<Object?>> _groups(SurfacesState state) => [
  for (final (level, rooms) in state.roomsByLevel) [level, ...rooms],
];

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

  SurfacesCubit build({
    List<Room> rooms = const [_living, _kitchen],
    Duration timeout = SurfacesCubit.defaultTimeout,
  }) {
    var next = 0;
    return SurfacesCubit(
      propertyRepository: repository,
      propertyId: 'p',
      rooms: rooms,
      generateId: () => 'new-${next++}',
      timeout: timeout,
    );
  }

  group(SurfacesCubit, () {
    test('starts with the saved rooms and their totals', () {
      final state = build().state;
      expect(state.rooms, [_living, _kitchen]);
      expect(state.livingArea, 51.3);
      expect(state.annexArea, 0);
      expect(state.hasAnnexes, isFalse);
      expect(state.mainRoomsCount, 1);
      expect(state.isValid, isTrue);
      expect(_groups(state), [
        [RoomLevel.groundFloor, _living, _kitchen],
      ]);
    });

    test('annexes count apart from the living area', () {
      const garage = Room(
        id: 'g',
        propertyId: 'p',
        name: 'Garage',
        areaM2: 18.25,
        isAnnex: true,
      );
      var state = build(rooms: const [_living, garage, _kitchen]).state;
      expect(state.livingArea, 51.3);
      expect(state.annexArea, 18.25);
      expect(state.hasAnnexes, isTrue);
      expect(state.isValid, isTrue);
      state = build(rooms: const [garage]).state;
      expect(state.livingArea, 0);
      expect(state.isValid, isFalse);
    });

    test('groups the rooms by level, rooms without a level last', () {
      const attic = Room(
        id: 'a',
        propertyId: 'p',
        name: 'Grenier',
        level: RoomLevel.attic,
        areaM2: 5,
      );
      const unknown = Room(id: 'u', propertyId: 'p', name: 'X', areaM2: 1);
      final state = build(rooms: const [unknown, attic, _kitchen]).state;
      expect(_groups(state), [
        [RoomLevel.groundFloor, _kitchen],
        [RoomLevel.attic, attic],
        [null, unknown],
      ]);
    });

    blocTest<SurfacesCubit, SurfacesState>(
      'roomAdded appends a room with a new id',
      build: build,
      act: (cubit) => cubit.roomAdded(_bedroom),
      expect: () => [
        const SurfacesState(
          rooms: [
            _living,
            _kitchen,
            Room(
              id: 'new-0',
              propertyId: 'p',
              name: 'Chambre 1',
              level: RoomLevel.firstFloor,
              areaM2: 12.35,
              isMain: true,
            ),
          ],
        ),
      ],
    );

    blocTest<SurfacesCubit, SurfacesState>(
      'roomEdited replaces the answers and keeps the other data',
      build: build,
      act: (cubit) => cubit.roomEdited(
        'r1',
        const RoomInput(name: 'Salon', level: RoomLevel.firstFloor, areaM2: 40),
      ),
      expect: () => [
        const SurfacesState(
          rooms: [
            Room(
              id: 'r1',
              propertyId: 'p',
              name: 'Salon',
              level: RoomLevel.firstFloor,
              areaM2: 40,
              ceilingHeightM: 2.5,
              photosCount: 4,
              source: RoomSource.scan,
            ),
            _kitchen,
          ],
        ),
      ],
    );

    blocTest<SurfacesCubit, SurfacesState>(
      'an annex is never a main room',
      build: () => build(rooms: const []),
      act: (cubit) => cubit.roomAdded(
        const RoomInput(
          name: 'Garage',
          level: RoomLevel.groundFloor,
          areaM2: 18,
          isMain: true,
          isAnnex: true,
        ),
      ),
      expect: () => [
        const SurfacesState(
          rooms: [
            Room(
              id: 'new-0',
              propertyId: 'p',
              name: 'Garage',
              level: RoomLevel.groundFloor,
              areaM2: 18,
              isAnnex: true,
            ),
          ],
        ),
      ],
    );

    blocTest<SurfacesCubit, SurfacesState>(
      'roomDeleted removes the room',
      build: build,
      act: (cubit) => cubit.roomDeleted('r1'),
      expect: () => [
        const SurfacesState(rooms: [_kitchen]),
      ],
    );

    blocTest<SurfacesCubit, SurfacesState>(
      'submit without rooms shows the error',
      build: () => build(rooms: const []),
      act: (cubit) => cubit.submit(),
      expect: () => [const SurfacesState(showErrors: true, submitAttempts: 1)],
      verify: (_) => verifyZeroInteractions(repository),
    );

    blocTest<SurfacesCubit, SurfacesState>(
      'submit with annexes only shows the error',
      build: () => build(rooms: const []),
      act: (cubit) async {
        cubit.roomAdded(
          const RoomInput(name: 'Cave', level: null, areaM2: 9, isAnnex: true),
        );
        await cubit.submit();
      },
      skip: 1,
      expect: () => [
        isA<SurfacesState>()
            .having((s) => s.showErrors, 'showErrors', isTrue)
            .having((s) => s.submitAttempts, 'submitAttempts', 1),
      ],
      verify: (_) => verifyZeroInteractions(repository),
    );

    blocTest<SurfacesCubit, SurfacesState>(
      'submit deletes removed rooms, skips unchanged ones and writes the '
      'others in table order',
      build: build,
      act: (cubit) async {
        cubit
          ..roomDeleted('r1')
          ..roomAdded(_bedroom);
        await cubit.submit();
      },
      skip: 2,
      expect: () => [
        isA<SurfacesState>().having(
          (s) => s.submission,
          'submission',
          SurfacesSubmission.inProgress,
        ),
        isA<SurfacesState>()
            .having(
              (s) => s.submission,
              'submission',
              SurfacesSubmission.success,
            )
            .having((s) => s.savedRooms.map((r) => r.id), 'saved', [
              'r2',
              'new-0',
            ]),
      ],
      verify: (_) {
        verify(() => repository.deleteRoom('r1')).called(1);
        final saved = verify(() => repository.saveRoom(captureAny())).captured
            .cast<Room>();
        // The kitchen moved to position 0, the bedroom is new.
        expect(saved.map((r) => (r.id, r.sortOrder)), [
          ('r2', 0),
          ('new-0', 1),
        ]);
      },
    );

    blocTest<SurfacesCubit, SurfacesState>(
      'submit writes a room whose position changed',
      build: () => build(rooms: const [_kitchen]),
      seed: () => const SurfacesState(rooms: [_kitchen]),
      act: (cubit) async {
        // Put the kitchen at its stored position.
        cubit.roomEdited('r2', RoomInput.fromRoom(_kitchen));
        await cubit.submit();
      },
      verify: (_) {
        // sort order 1 → 0: written once.
        verify(() => repository.saveRoom(any())).called(1);
      },
    );

    test('a second submission does not write the rooms again', () async {
      final cubit = build();
      await cubit.submit();
      clearInteractions(repository);
      await cubit.submit();
      verifyNever(() => repository.saveRoom(any()));
      verifyNever(() => repository.deleteRoom(any()));
      expect(cubit.state.submission, SurfacesSubmission.success);
    });

    test('edits are ignored while submitting', () async {
      final completer = Completer<Room>();
      when(() => repository.saveRoom(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build(rooms: const [])..roomAdded(_bedroom);
      final submission = cubit.submit();
      expect(cubit.state.isSubmitting, isTrue);
      final rooms = cubit.state.rooms;
      cubit
        ..roomAdded(_bedroom)
        ..roomDeleted('new-0');
      await cubit.submit();
      expect(cubit.state.rooms, rooms);
      completer.complete(rooms.single);
      await submission;
      expect(cubit.state.submission, SurfacesSubmission.success);
    });

    test('after a failed write, retrying updates the same row; a room '
        'removed meanwhile is deleted', () async {
      when(() => repository.saveRoom(any())).thenThrow(Exception('lost'));
      final cubit = build(rooms: const [])..roomAdded(_bedroom);
      await cubit.submit();
      expect(cubit.state.submission, SurfacesSubmission.failure);

      when(() => repository.saveRoom(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments.single as Room,
      );
      await cubit.submit();
      final ids = verify(() => repository.saveRoom(captureAny())).captured
          .cast<Room>()
          .map((r) => r.id);
      expect(ids, ['new-0', 'new-0']);

      // Its row may exist although its write failed: removed, it is deleted.
      when(() => repository.saveRoom(any())).thenThrow(Exception('lost'));
      cubit.roomAdded(_bedroom);
      await cubit.submit();
      cubit.roomDeleted('new-1');
      await cubit.submit();
      verify(() => repository.deleteRoom('new-1')).called(1);
      expect(cubit.state.submission, SurfacesSubmission.success);
    });

    test('a write that takes too long fails', () async {
      when(() => repository.saveRoom(any()))
          .thenAnswer((_) => Completer<Room>().future);
      final cubit = build(timeout: const Duration(milliseconds: 10))
        ..roomDeleted('r1');
      await cubit.submit();
      expect(cubit.state.submission, SurfacesSubmission.failure);
    });

    test('closing while saving emits nothing more', () async {
      final saveCompleter = Completer<Room>();
      when(() => repository.saveRoom(any()))
          .thenAnswer((_) => saveCompleter.future);
      var cubit = build(rooms: const [])..roomAdded(_bedroom);
      var submission = cubit.submit();
      await cubit.close();
      saveCompleter.complete(cubit.state.rooms.single);
      await submission;

      final failure = Completer<Room>();
      when(() => repository.saveRoom(any())).thenAnswer((_) => failure.future);
      cubit = build(rooms: const [])..roomAdded(_bedroom);
      submission = cubit.submit();
      await cubit.close();
      failure.completeError(Exception());
      await submission;
      expect(cubit.state.isSubmitting, isTrue);
    });

    test('closing while deleting stops the writes', () async {
      final completer = Completer<void>();
      when(() => repository.deleteRoom(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()..roomDeleted('r1');
      final submission = cubit.submit();
      await cubit.close();
      completer.complete();
      await submission;
      verifyNever(() => repository.saveRoom(any()));
      // Edits after closing are ignored.
      cubit.roomDeleted('r2');
    });

    test('a failure reports the rows stored so far', () async {
      when(() => repository.saveRoom(any())).thenThrow(Exception());
      final cubit = build()..roomDeleted('r1');
      await cubit.submit();
      expect(cubit.state.submission, SurfacesSubmission.failure);
      expect(cubit.state.savedRooms, [_kitchen]);
    });

    test('randomUuid makes version 4 UUIDs', () {
      final id = SurfacesCubit.randomUuid();
      expect(
        id,
        matches(
          RegExp(
            '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
      expect(SurfacesCubit.randomUuid(), isNot(id));
      final cubit = SurfacesCubit(
        propertyRepository: repository,
        propertyId: 'p',
      )..roomAdded(_bedroom);
      expect(cubit.state.rooms.single.id, hasLength(36));
    });
  });
}
