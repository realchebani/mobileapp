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
      expect(turn.props, hasLength(10));
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
    expect(const AgentPill(field: 'a', label: 'b').props, ['a', 'b']);
    expect(AgentStep.lifestyle.value, 'lifestyle');
    expect(const Transcription(turnId: 'a', transcript: 'b').props, ['a', 'b']);
    expect(const AgentLifestyleItem(isAsset: true, label: 'x').props, [
      true,
      'x',
    ]);
  });
}
