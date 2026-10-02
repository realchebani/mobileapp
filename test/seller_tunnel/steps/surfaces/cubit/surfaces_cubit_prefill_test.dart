import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/cubit/surfaces_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

PendingAnswer _pending(String id, Map<String, Object?> values) => PendingAnswer(
  id: id,
  propertyId: 'p',
  targetStep: 'rooms',
  kind: PendingKind.room,
  value: values,
  label: id,
  quote: 'q',
  sourceStep: 'context',
  turnId: 't0',
);

/// EPIC-16: rooms said on another step, appended notes.
void main() {
  late MockPropertyRepository repository;
  final at = DateTime.utc(2026, 10, 2);

  setUpAll(
    () => registerFallbackValue(
      const Room(propertyId: 'p', name: 'x', areaM2: 1),
    ),
  );

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.saveRoom(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as Room,
    );
    when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
    when(() => repository.deleteRoomPhotos(any())).thenAnswer((_) async {});
  });

  SurfacesCubit build(List<PendingAnswer> pending) {
    var ids = 0;
    return SurfacesCubit(
      propertyRepository: repository,
      propertyId: 'p',
      rooms: const [
        Room(
          id: 'r0',
          propertyId: 'p',
          name: 'Séjour',
          areaM2: 30,
          isMain: true,
        ),
      ],
      pendingRooms: pending,
      generateId: () => 'n${ids++}',
      clock: () => at,
    );
  }

  test(
    'pending rooms join the table « À confirmer », resolved on submit',
    () async {
      final cubit = build([
        _pending('kept', {'name': 'Cuisine', 'area_m2': 12, 'kind': 'kitchen'}),
        _pending('edited', {'name': 'Bureau', 'area_m2': 9}),
        _pending('redictated', {'name': 'Cellier', 'area_m2': 4}),
        _pending('removed', {'name': 'Cave', 'area_m2': 8}),
        _pending('confirmed', {
          'name': 'Chambre',
          'area_m2': 11,
          'kind': 'bedroom',
        }),
        _pending('invalid', {'name': 'Grenier'}),
      ]);
      expect(cubit.state.rooms.map((r) => r.name), [
        'Séjour',
        'Cuisine',
        'Bureau',
        'Cellier',
        'Cave',
        'Chambre 1',
      ]);
      expect(cubit.state.toConfirm, {
        'n0': 'kept',
        'n1': 'edited',
        'n2': 'redictated',
        'n3': 'removed',
        'n4': 'confirmed',
      });
      cubit
        ..roomEdited(
          'n1',
          const RoomInput(name: 'Bureau', level: null, areaM2: 10),
        )
        ..roomEdited(
          'r0',
          const RoomInput(
            name: 'Séjour',
            level: null,
            areaM2: 31,
            isMain: true,
          ),
        )
        ..roomDeleted('n3');
      await cubit.voiceTurnApplied(
        const AgentTurn(
          turnId: 't1',
          transcript: '',
          reply: '',
          entityOps: [
            AgentEntityChange(
              entity: AgentEntity.room,
              op: AgentEntityOp.update,
              target: 'R4',
              label: 'Cellier',
              values: {'area_m2': 5, 'description': 'Étagères'},
            ),
            AgentEntityChange(
              entity: AgentEntity.room,
              op: AgentEntityOp.update,
              target: 'R4',
              label: 'Cellier',
              values: {'description': 'Étagères'},
            ),
            AgentEntityChange(
              entity: AgentEntity.room,
              op: AgentEntityOp.update,
              target: 'R4',
              label: 'Cellier',
              values: {'description': 'Fenêtre'},
            ),
          ],
        ),
      );
      final cellier = cubit.state.rooms.firstWhere((r) => r.name == 'Cellier');
      // Notes said again are appended once.
      expect(cellier.description, 'Étagères · Fenêtre');
      expect(cubit.state.toConfirm.keys, ['n0', 'n4']);
      await cubit.submit(confirmed: {'confirmed'});
      expect(cubit.state.pendingResolutions, {
        PendingResolution.continueTapped: ['kept'],
        PendingResolution.modified: ['edited'],
        PendingResolution.replaced: ['redictated'],
        PendingResolution.erased: ['removed'],
        PendingResolution.yes: ['confirmed'],
      });
      final saved = cubit.state.savedRooms;
      final kitchen = saved.firstWhere((r) => r.name == 'Cuisine');
      expect(sourceKinds(kitchen), {
        'name': 'dicte_autre_etape',
        'area_m2': 'dicte_autre_etape',
      });
      final bedroom = saved.firstWhere((r) => r.name == 'Chambre 1');
      expect((bedroom.fieldSources['area_m2']! as Map)['c'], 'oui');
      expect(sourceKinds(saved.first), {'area_m2': 'saisi'});
      expect(
        sourceKinds(saved.firstWhere((r) => r.name == 'Bureau'))['area_m2'],
        'saisi',
      );
    },
  );

  test('notes said are cut to 600 characters', () async {
    final cubit = build(const []);
    await cubit.voiceTurnApplied(
      AgentTurn(
        turnId: 't1',
        transcript: '',
        reply: '',
        entityOps: [
          AgentEntityChange(
            entity: AgentEntity.room,
            op: AgentEntityOp.update,
            target: 'R1',
            label: 'Séjour',
            values: {'description': 'x' * 700},
          ),
        ],
      ),
    );
    expect(cubit.state.rooms.single.description, hasLength(600));
  });

  test('a room prepared for its photos keeps its pending origin', () async {
    final cubit = build([
      _pending('kept', {'name': 'Cuisine', 'area_m2': 12}),
    ]);
    await cubit.preparePhotos('n0');
    expect(sourceKinds(cubit.state.photosRoom!)['name'], 'dicte_autre_etape');
  });
}
