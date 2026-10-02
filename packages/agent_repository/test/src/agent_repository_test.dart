import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

class _MockFunctionsClient extends Mock implements FunctionsClient;

void main() {
  late _MockFunctionsClient functions;
  late AgentRepository repository;

  setUp(() {
    functions = _MockFunctionsClient();
    repository = AgentRepository(functions: functions);
  });

  void answer(Object? data) => when(
    () => functions.invoke(
      any(),
      body: any(named: 'body'),
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenAnswer((_) async => FunctionResponse(data: data, status: 200));

  void fail(Object error) => when(
    () => functions.invoke(
      any(),
      body: any(named: 'body'),
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenThrow(error);

  group('transcribe', () {
    test('sends the audio with its context', () async {
      answer({'turn_id': 't1', 'transcript': 'Bonjour'});
      final audio = Uint8List.fromList([1, 2]);
      final result = await repository.transcribe(
        propertyId: 'p1',
        step: AgentStep.technical,
        audio: audio,
        duration: const Duration(milliseconds: 2500),
      );
      expect(result, const Transcription(turnId: 't1', transcript: 'Bonjour'));
      verify(
        () => functions.invoke(
          'agent-transcribe',
          body: audio,
          queryParameters: {
            'property_id': 'p1',
            'step': 'technical',
            'format': 'm4a',
            'duration': '2.50',
          },
        ),
      ).called(1);
    });

    test('maps the failures', () async {
      Future<Object?> failure(int status, [Object? details]) async {
        fail(FunctionsHttpException(status: status, details: details));
        try {
          await repository.transcribe(
            propertyId: 'p1',
            step: AgentStep.technical,
            audio: Uint8List(1),
            duration: Duration.zero,
          );
        } on AgentFailure catch (error) {
          return error;
        }
        return null;
      }

      expect(
        await failure(409, {'error': 'locked'}),
        isA<AgentLockedFailure>(),
      );
      expect(await failure(429), isA<AgentQuotaFailure>());
      expect(await failure(422), isA<AgentEmptyFailure>());
      expect(await failure(413), isA<AgentTooLongFailure>());
      final upstream = await failure(502, {
        'error': 'upstream',
        'turn_id': 't9',
      });
      expect(upstream, isA<AgentRequestFailure>());
      expect((upstream! as AgentRequestFailure).turnId, 't9');
      expect(await failure(409, 'text'), isA<AgentRequestFailure>());
      fail(Exception('offline'));
      await expectLater(
        repository.transcribe(
          propertyId: 'p1',
          step: AgentStep.lifestyle,
          audio: Uint8List(1),
          duration: Duration.zero,
        ),
        throwsA(isA<AgentRequestFailure>()),
      );
    });

    test('times out', () async {
      repository = AgentRepository(
        functions: functions,
        timeout: const Duration(milliseconds: 1),
      );
      when(
        () => functions.invoke(
          any(),
          body: any(named: 'body'),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) => Completer<FunctionResponse>().future);
      await expectLater(
        repository.transcribe(
          propertyId: 'p1',
          step: AgentStep.technical,
          audio: Uint8List(1),
          duration: Duration.zero,
        ),
        throwsA(isA<AgentRequestFailure>()),
      );
    });
  });

  group('turn', () {
    test('parses the answer', () async {
      answer({
        'turn_id': 't1',
        'transcript': 'date de 1998',
        'reply_fr': 'Merci.',
        'patch': {'construction_year': 1998},
        'facts': [
          {'field': 'construction_year', 'label_fr': 'Construction 1998'},
        ],
        'pending': [
          {'field': 'sanitation', 'label_fr': 'Assainissement ?'},
        ],
        'lifestyle_items': [
          {'kind': 'asset', 'label': 'Calme'},
          {'kind': 'watch_point', 'label': 'Bus rare'},
        ],
        'suggestions': {'secret_note': 'Vendre vite'},
        'next_field': 'sanitation',
        'done': true,
      });
      final turn = await repository.turn(
        propertyId: 'p1',
        step: AgentStep.lifestyle,
        transcript: 'date de 1998',
        assetLabels: ['Vue'],
      );
      expect(turn.patch, {'construction_year': 1998});
      expect(turn.facts.single.label, 'Construction 1998');
      expect(turn.pending.single.field, 'sanitation');
      expect(turn.lifestyleItems, const [
        AgentLifestyleItem(isAsset: true, label: 'Calme'),
        AgentLifestyleItem(isAsset: false, label: 'Bus rare'),
      ]);
      expect(turn.suggestions, {'secret_note': 'Vendre vite'});
      expect(turn.nextField, 'sanitation');
      expect(turn.done, isTrue);
      expect(turn.props, hasLength(14));
      verify(
        () => functions.invoke(
          'agent-turn',
          body: {
            'property_id': 'p1',
            'step': 'lifestyle',
            'transcript': 'date de 1998',
            'lifestyle_labels': {
              'asset': ['Vue'],
              'watch_point': <String>[],
            },
          },
        ),
      ).called(1);
    });

    test('minimal answer', () async {
      answer({'turn_id': 't1'});
      final turn = await repository.turn(
        propertyId: 'p1',
        step: AgentStep.technical,
        turnId: 't1',
      );
      expect(turn, const AgentTurn(turnId: 't1', transcript: '', reply: ''));
    });
  });

  group('EPIC-14', () {
    test('dictation transcribes only', () async {
      answer({'turn_id': 't1', 'transcript': '12 rue des Lilas'});
      await repository.transcribe(
        propertyId: 'p1',
        step: AgentStep.location,
        audio: Uint8List(1),
        duration: Duration.zero,
        dictation: true,
      );
      verify(
        () => functions.invoke(
          'agent-transcribe',
          body: any(named: 'body'),
          queryParameters: {
            'property_id': 'p1',
            'step': 'location',
            'format': 'm4a',
            'duration': '0.00',
            'mode': 'dictation',
          },
        ),
      ).called(1);
    });

    test('sends the step context and parses entities', () async {
      answer({
        'turn_id': 't1',
        'transcript': 'le séjour fait 40 m²',
        'reply_fr': 'Noté.',
        'patch': {'purchase_year': 2012},
        'facts': [
          {
            'field': 'purchase_year',
            'label_fr': 'Achat 2012',
            'changed_fr': 'Modifié : 2010 → 2012',
            'corrected': true,
          },
        ],
        'entity_ops': [
          {
            'entity': 'room',
            'op': 'update',
            'target': 'R1',
            'values': {'area_m2': 40},
            'label_fr': 'Séjour · 40 m²',
            'changed_fr': 'Modifiée : 38 → 40 m²',
            'corrected': true,
          },
          {'entity': 'nope', 'op': 'nope'},
        ],
        'confirmations': [
          {
            'id': 'c1',
            'reason': 'delete',
            'label_fr': 'Supprimer Cellier ?',
            'entity_ops': [
              {
                'entity': 'room',
                'op': 'delete',
                'target': 'R2',
                'label_fr': 'Supprimer Cellier',
              },
            ],
          },
          {
            'id': 'c2',
            'reason': 'unknown',
            'label_fr': 'Type : garage ?',
            'patch': {'property_type': 'stationnement'},
          },
        ],
        'out_of_step': [
          {
            'field': 'construction_year',
            'step': 'technical',
            'label_fr': 'Construction → Technique',
          },
        ],
        'corrections': ['room:R1'],
      });
      final turn = await repository.turn(
        propertyId: 'p1',
        step: AgentStep.rooms,
        transcript: 'le séjour fait 40 m²',
        context: AgentTurnContext(
          draft: const {'purchase_year': 2010},
          rooms: const [
            AgentRoom(ref: 'R1', name: 'Séjour', areaM2: 38, level: 'rdc'),
          ],
          estimates: [
            AgentEstimate(
              ref: 'E1',
              priceEur: 300000,
              month: DateTime(2024, 3),
              agencyName: 'A',
            ),
            const AgentEstimate(ref: 'E2'),
          ],
          coOwnersCount: 1,
          lastRoomRef: 'R1',
        ),
        undoneTurnIds: const ['t0'],
      );
      expect(turn.facts.single.changedLabel, 'Modifié : 2010 → 2012');
      expect(turn.facts.single.corrected, isTrue);
      expect(turn.entityOps.first.entity, AgentEntity.room);
      expect(turn.entityOps.first.op, AgentEntityOp.update);
      expect(turn.entityOps.first.isNew, isFalse);
      expect(turn.entityOps.first.values, {'area_m2': 40});
      expect(turn.entityOps.first.changedLabel, 'Modifiée : 38 → 40 m²');
      expect(turn.entityOps.first.corrected, isTrue);
      expect(turn.entityOps.last.entity, AgentEntity.room);
      expect(turn.entityOps.last.op, AgentEntityOp.create);
      expect(turn.entityOps.last.isNew, isTrue);
      expect(turn.confirmations.first.reason, AgentConfirmationReason.delete);
      expect(
        turn.confirmations.first.entityOps.single.op,
        AgentEntityOp.delete,
      );
      expect(
        turn.confirmations.last.reason,
        AgentConfirmationReason.mediumConfidence,
      );
      expect(turn.outOfStep.single.step, 'technical');
      expect(turn.corrections, ['room:R1']);
      expect(turn.understood, isTrue);
      verify(
        () => functions.invoke(
          'agent-turn',
          body: {
            'property_id': 'p1',
            'step': 'rooms',
            'transcript': 'le séjour fait 40 m²',
            'interactive': true,
            'draft': {'purchase_year': 2010},
            'rooms': [
              {
                'ref': 'R1',
                'name': 'Séjour',
                'area_m2': 38.0,
                'level': 'rdc',
                'floor_covering': null,
                'glazing': null,
                'ceiling_height_m': null,
                'is_annex': false,
              },
            ],
            'estimates': [
              {
                'ref': 'E1',
                'price_eur': 300000,
                'estimated_month': '2024-03-01',
                'agency_name': 'A',
              },
              {
                'ref': 'E2',
                'price_eur': null,
                'estimated_month': null,
                'agency_name': null,
              },
            ],
            'co_owners_count': 1,
            'last_room_ref': 'R1',
            'undone_turn_ids': ['t0'],
          },
        ),
      ).called(1);
    });

    test('a turn without the pill the seller undid', () {
      const turn = AgentTurn(
        turnId: 't1',
        transcript: 'x',
        reply: 'y',
        patch: {'a': 1, 'b': 2},
        facts: [
          AgentPill(field: 'a', label: 'A'),
          AgentPill(field: 'b', label: 'B'),
        ],
        entityOps: [
          AgentEntityChange(
            entity: AgentEntity.room,
            op: AgentEntityOp.create,
            target: 'new',
            label: 'R',
          ),
          AgentEntityChange(
            entity: AgentEntity.room,
            op: AgentEntityOp.update,
            target: 'R1',
            label: 'S',
          ),
        ],
      );
      final withoutA = turn.without('a');
      expect(withoutA.patch, {'b': 2});
      expect(withoutA.facts.single.field, 'b');
      expect(withoutA.entityOps, hasLength(2));
      final withoutOp = turn.without('op:0');
      expect(withoutOp.patch, {'a': 1, 'b': 2});
      expect(withoutOp.entityOps.single.target, 'R1');
      expect(
        const AgentTurn(turnId: 't', transcript: '', reply: '').understood,
        isFalse,
      );
    });

    test('a confirmed change is a turn of its own', () {
      final turn = AgentTurn.confirmed(
        't1',
        const AgentConfirmation(
          id: 'c1',
          reason: AgentConfirmationReason.typeChange,
          label: 'Type : garage\u00a0?',
          patch: {'property_type': 'stationnement'},
        ),
      );
      expect(turn.turnId, 't1#c1');
      expect(turn.patch, {'property_type': 'stationnement'});
      expect(turn.facts.single.label, 'Type : garage');
      expect(turn.facts.single.field, 'property_type');
      final delete = AgentTurn.confirmed(
        't1',
        const AgentConfirmation(
          id: 'c2',
          reason: AgentConfirmationReason.delete,
          label: 'Supprimer ?',
          entityOps: [
            AgentEntityChange(
              entity: AgentEntity.room,
              op: AgentEntityOp.delete,
              target: 'R2',
              label: 'Supprimer Cellier',
            ),
          ],
        ),
      );
      expect(delete.facts, isEmpty);
      expect(delete.entityOps.single.target, 'R2');
    });

    test('rooms summary and undone turns', () async {
      answer({'turn_id': 't9', 'reply_fr': 'J’ai noté 1 pièce.'});
      final summary = await repository.roomsSummary(
        propertyId: 'p1',
        rooms: const [AgentRoom(ref: 'R1', name: 'Séjour', areaM2: 20)],
      );
      expect(summary.reply, 'J’ai noté 1 pièce.');
      verify(
        () => functions.invoke(
          'agent-turn',
          body: {
            'property_id': 'p1',
            'step': 'rooms',
            'summary': true,
            'rooms': [
              {
                'ref': 'R1',
                'name': 'Séjour',
                'area_m2': 20.0,
                'level': null,
                'floor_covering': null,
                'glazing': null,
                'ceiling_height_m': null,
                'is_annex': false,
              },
            ],
          },
        ),
      ).called(1);
      answer({'undone': 1});
      await repository.markUndone(
        propertyId: 'p1',
        step: AgentStep.owners,
        turnIds: const ['t1'],
      );
      verify(
        () => functions.invoke(
          'agent-turn',
          body: {
            'property_id': 'p1',
            'step': 'owners',
            'undone_turn_ids': ['t1'],
          },
        ),
      ).called(1);
      await repository.markUndone(
        propertyId: 'p1',
        step: AgentStep.owners,
        turnIds: const [],
      );
      verifyNoMoreInteractions(functions);
    });

    test('model props', () {
      expect(
        const AgentEntityChange(
          entity: AgentEntity.coOwner,
          op: AgentEntityOp.create,
          target: 'new',
          label: 'x',
        ).props,
        hasLength(7),
      );
      expect(
        const AgentConfirmation(
          id: 'c',
          reason: AgentConfirmationReason.coOwner,
          label: 'x',
        ).props,
        hasLength(5),
      );
      expect(const AgentOutOfStep(field: 'a', step: 'b', label: 'c').props, [
        'a',
        'b',
        'c',
      ]);
      expect(
        const AgentRoom(ref: 'R1', name: 'a', areaM2: 1).props,
        hasLength(8),
      );
      expect(const AgentEstimate(ref: 'E1').props, hasLength(4));
      expect(const AgentTurnContext().props, hasLength(6));
      expect(const AgentTurnContext(interactive: false).toJson(), {
        'interactive': false,
      });
      expect(AgentEntity.parse('co_owner'), AgentEntity.coOwner);
      expect(AgentEntity.parse('x'), isNull);
      expect(AgentEntityOp.parse('delete'), AgentEntityOp.delete);
      expect(
        AgentConfirmationReason.parse('merge_room'),
        AgentConfirmationReason.mergeRoom,
      );
      expect(AgentStep.values.map((s) => s.value), [
        'owners',
        'location',
        'context',
        'technical',
        'rooms',
        'lifestyle',
      ]);
    });
  });

  group('speech', () {
    test('returns mp3 or wav bytes', () async {
      answer(Uint8List.fromList([0x49, 0x44, 0x33]));
      expect((await repository.speech('t1')).format, 'mp3');
      answer(Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0]));
      final wav = await repository.speech('t1');
      expect(wav.format, 'wav');
      expect(wav.props, hasLength(2));
      answer(Uint8List.fromList([0x52, 0x49, 0x46, 0]));
      expect((await repository.speech('t1')).format, 'mp3');
    });

    test('fails without audio', () async {
      answer('text');
      await expectLater(
        repository.speech('t1'),
        throwsA(isA<AgentRequestFailure>()),
      );
      fail(const FunctionsHttpException(status: 409, details: {'error': 'x'}));
      await expectLater(
        repository.speech('t1'),
        throwsA(isA<AgentRequestFailure>()),
      );
    });
  });

  test('failures print their name', () {
    expect(const AgentLockedFailure().toString(), 'AgentLockedFailure(null)');
    expect(const AgentQuotaFailure(1).toString(), 'AgentQuotaFailure(1)');
    expect(const AgentEmptyFailure().toString(), 'AgentEmptyFailure(null)');
    expect(const AgentTooLongFailure().toString(), 'AgentTooLongFailure(null)');
    expect(const AgentRequestFailure().toString(), 'AgentRequestFailure(null)');
  });

  test('model equality', () {
    expect(const AgentPill(field: 'a', label: 'b').props, [
      'a',
      'b',
      null,
      false,
    ]);
    expect(AgentStep.lifestyle.value, 'lifestyle');
    expect(const Transcription(turnId: 'a', transcript: 'b').props, ['a', 'b']);
    expect(const AgentLifestyleItem(isAsset: true, label: 'x').props, [
      true,
      'x',
    ]);
  });
}
