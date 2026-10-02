import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/cubit/surfaces_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _living = Room(
  id: 'r1',
  propertyId: 'p',
  name: 'Séjour',
  level: RoomLevel.groundFloor,
  areaM2: 38,
  floorCovering: 'parquet_chene',
  glazing: Glazing.double,
  isMain: true,
);

const _bedroom = Room(
  id: 'r2',
  propertyId: 'p',
  name: 'Chambre 1',
  level: RoomLevel.firstFloor,
  areaM2: 12,
  isMain: true,
  sortOrder: 1,
);

AgentEntityChange _op(
  AgentEntityOp op,
  String target, [
  Map<String, Object?> values = const {},
]) => AgentEntityChange(
  entity: AgentEntity.room,
  op: op,
  target: target,
  label: 'x',
  values: values,
);

AgentTurn _turn(String id, List<AgentEntityChange> ops) =>
    AgentTurn(turnId: id, transcript: '', reply: '', entityOps: ops);

void main() {
  var ids = 0;

  SurfacesCubit build([List<Room> rooms = const [_living, _bedroom]]) =>
      SurfacesCubit(
        propertyRepository: MockPropertyRepository(),
        propertyId: 'p',
        rooms: rooms,
        generateId: () => 'new-${++ids}',
      );

  setUp(() => ids = 0);

  group('SurfacesCubit voice', () {
    test('sends the table with short references', () async {
      final cubit = build();
      expect(cubit.voiceContext.rooms, const [
        AgentRoom(
          ref: 'R1',
          name: 'Séjour',
          areaM2: 38,
          level: 'rdc',
          floorCovering: 'parquet_chene',
          glazing: 'double',
        ),
        AgentRoom(ref: 'R2', name: 'Chambre 1', areaM2: 12, level: 'etage_1'),
      ]);
      expect(cubit.voiceContext.lastRoomRef, isNull);
      expect(cubit.voiceContext.interactive, isTrue);
      await cubit.close();
    });

    test('creates numbered bedrooms on the last level, as dictated', () async {
      final cubit = build();
      await cubit.voiceTurnApplied(
        _turn('t1', [
          _op(AgentEntityOp.create, 'new', {
            'name': 'Chambre',
            'kind': 'bedroom',
            'area_m2': 11,
            'floor_covering': 'parquet',
            'glazing': 'triple',
            'ceiling_height_m': 2.5,
            'description': 'Placard intégré',
          }),
          _op(AgentEntityOp.create, 'new', {
            'name': 'Cellier',
            'kind': 'storeroom',
            'area_m2': 4.2,
            'level': 'sous_sol',
          }),
          _op(AgentEntityOp.create, 'new', {'name': 'Véranda', 'area_m2': 15}),
          // Incomplete: ignored.
          _op(AgentEntityOp.create, 'new', {'name': ' ', 'area_m2': 3}),
          _op(AgentEntityOp.create, 'new', {'name': 'Bureau'}),
        ]),
      );
      final rooms = cubit.state.rooms;
      expect(rooms, hasLength(5));
      expect(
        rooms[2],
        const Room(
          id: 'new-1',
          propertyId: 'p',
          name: 'Chambre 2',
          level: RoomLevel.firstFloor,
          areaM2: 11,
          floorCovering: 'parquet',
          glazing: Glazing.triple,
          ceilingHeightM: 2.5,
          isMain: true,
          source: RoomSource.voice,
          description: 'Placard intégré',
        ),
      );
      expect(rooms[3].isAnnex, isTrue);
      expect(rooms[3].isMain, isFalse);
      expect(rooms[3].level, RoomLevel.basement);
      // A level not said: the one of the last room.
      expect(rooms[4].level, RoomLevel.basement);
      expect(rooms[4].isMain, isFalse);
      expect(cubit.state.dictated, {'new-1', 'new-2', 'new-3'});
      expect(cubit.state.lastDictatedId, 'new-3');
      expect(cubit.state.dictatedRooms.map((r) => r.id), [
        'new-1',
        'new-2',
        'new-3',
      ]);
      expect(cubit.voiceContext.lastRoomRef, 'R5');
      await cubit.close();
    });

    test(
      'updates and deletes by reference; unknown ones are ignored',
      () async {
        final cubit = build();
        await cubit.voiceTurnApplied(
          _turn('t1', [
            _op(AgentEntityOp.update, 'R1', {
              'area_m2': 40,
              'level': 'etage_2',
              'floor_covering': null,
              'glazing': 'nope',
            }),
            _op(AgentEntityOp.delete, 'R2'),
            _op(AgentEntityOp.update, 'R9', {'area_m2': 1}),
            const AgentEntityChange(
              entity: AgentEntity.previousEstimate,
              op: AgentEntityOp.create,
              target: 'new',
              label: 'x',
            ),
          ]),
        );
        expect(cubit.state.rooms, [
          const Room(
            id: 'r1',
            propertyId: 'p',
            name: 'Séjour',
            level: RoomLevel.secondFloor,
            areaM2: 40,
            glazing: Glazing.double,
            isMain: true,
          ),
        ]);
        expect(cubit.state.dictated, {'r1'});
        // A level not said is kept.
        await cubit.voiceTurnApplied(
          _turn('t1b', [
            _op(AgentEntityOp.update, 'R1', {'description': 'Lumineux'}),
          ]),
        );
        expect(cubit.state.rooms.single.level, RoomLevel.secondFloor);
        expect(cubit.state.rooms.single.description, 'Lumineux');
        await cubit.voiceTurnApplied(
          _turn('t2', [_op(AgentEntityOp.delete, 'R1')]),
        );
        expect(cubit.state.rooms, isEmpty);
        expect(cubit.state.dictated, isEmpty);
        expect(cubit.state.lastDictatedId, isNull);
        // Undo restores both turns' rooms.
        cubit.undoVoiceTurnsFrom(0);
        expect(cubit.state.rooms, const [_living, _bedroom]);
        await cubit.close();
      },
    );

    test('no voice while saving', () async {
      final cubit = build();
      expect(cubit.acceptsVoice, isTrue);
      await cubit.close();
    });
  });

  group(RoomSuggestion, () {
    test('byKind and numbered', () {
      expect(RoomSuggestion.byKind('bedroom'), RoomSuggestion.bedroom);
      expect(RoomSuggestion.byKind('nope'), isNull);
      expect(RoomSuggestion.numbered('Chambre', const []), 'Chambre 1');
      expect(
        RoomSuggestion.numbered('Chambre', const [
          'Chambre',
          'Chambre 3',
          'Cuisine',
        ]),
        'Chambre 4',
      );
    });
  });

  test('an undo replays the later turns on the same rooms (ids)', () async {
    final cubit = build();
    // R1 is the living room, then (once it is deleted) the bedroom.
    await cubit.voiceTurnApplied(
      _turn('t1', [_op(AgentEntityOp.delete, 'R1')]),
    );
    await cubit.voiceTurnApplied(
      _turn('t2', [
        _op(AgentEntityOp.update, 'R1', {'area_m2': 13}),
      ]),
    );
    expect(cubit.state.rooms.single.areaM2, 13);
    cubit.undoVoiceTurn('t1');
    expect(cubit.state.rooms.map((r) => (r.id, r.areaM2)), [
      ('r1', 38.0),
      ('r2', 13.0),
    ]);
    await cubit.close();
  });
}
