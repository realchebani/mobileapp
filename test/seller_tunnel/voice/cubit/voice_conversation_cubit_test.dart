import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_repository/voice_repository.dart';

import '../../../helpers/helpers.dart';

const _turn = AgentTurn(
  turnId: 't1',
  transcript: 'date de 1998',
  reply: 'Merci. Et la toiture ?',
  facts: [AgentPill(field: 'construction_year', label: 'Construction 1998')],
  pending: [
    AgentPill(field: 'sanitation', label: 'Assainissement ?'),
    AgentPill(field: 'construction_year', label: 'Construction ?'),
  ],
);

void main() {
  late MockAgentRepository agent;
  late MockVoiceRecorder recorder;
  late MockVoicePlayer player;
  late VoicePreferences preferences;
  late StreamController<double> levels;
  late List<AgentTurn> applied;
  late DateTime now;
  Exception? applyError;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AgentStep.technical);
  });

  setUp(() async {
    agent = MockAgentRepository();
    recorder = MockVoiceRecorder();
    player = MockVoicePlayer();
    preferences = (await testVoiceServices()).preferences!;
    levels = StreamController<double>.broadcast();
    applied = [];
    applyError = null;
    now = DateTime(2026, 10, 1, 10);
    when(() => recorder.requestPermission()).thenAnswer((_) async => true);
    when(() => recorder.start()).thenAnswer((_) async {});
    when(() => recorder.levels()).thenAnswer((_) => levels.stream);
    when(() => recorder.cancel()).thenAnswer((_) async {});
    when(() => recorder.dispose()).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer(
      (_) async => RecordedAudio(
        bytes: Uint8List.fromList([1]),
        duration: const Duration(seconds: 2),
      ),
    );
    when(() => player.play(any(), format: any(named: 'format')))
        .thenAnswer((_) async {});
    when(() => player.stop()).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});
    when(
      () => agent.transcribe(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        audio: any(named: 'audio'),
        duration: any(named: 'duration'),
        format: any(named: 'format'),
      ),
    ).thenAnswer(
      (_) async =>
          const Transcription(turnId: 't1', transcript: 'date de 1998'),
    );
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
      ),
    ).thenAnswer((_) async => _turn);
    when(() => agent.speech(any())).thenAnswer(
      (_) async => AgentSpeech(bytes: Uint8List.fromList([2]), format: 'wav'),
    );
  });

  tearDown(() => levels.close());

  VoiceConversationCubit build() => VoiceConversationCubit(
    agentRepository: agent,
    recorder: recorder,
    player: player,
    preferences: preferences,
    propertyId: 'p1',
    step: AgentStep.technical,
    intro: 'Bonjour',
    onTurn: (turn) async {
      if (applyError case final error?) throw error;
      applied.add(turn);
    },
    assetLabels: () => ['Calme'],
    watchPointLabels: () => [],
    clock: () => now,
  );

  /// Speaks then stays silent until the end of speech is detected.
  Future<void> speak() async {
    levels.add(-20);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(milliseconds: 300));
    levels.add(-60);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 2));
    levels.add(-60);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('default labels are empty', () async {
    final cubit = VoiceConversationCubit(
      agentRepository: agent,
      recorder: recorder,
      player: player,
      preferences: preferences,
      propertyId: 'p1',
      step: AgentStep.lifestyle,
      intro: 'Bonjour',
      onTurn: (_) async {},
    );
    await cubit.start();
    await cubit.finishSpeaking();
    expect(cubit.state.error, VoiceError.empty);
    levels.add(-20);
    await cubit.retry();
    await Future<void>.delayed(Duration.zero);
    levels.add(-20);
    await Future<void>.delayed(Duration.zero);
    await cubit.finishSpeaking();
    verify(
      () => agent.turn(
        propertyId: 'p1',
        step: AgentStep.lifestyle,
        turnId: 't1',
        assetLabels: [],
        watchPointLabels: [],
      ),
    ).called(1);
    await cubit.close();
  });

  test('initial state: the intro, muted from the preferences', () {
    final cubit = build();
    expect(cubit.state.messages, const [
      VoiceMessage(text: 'Bonjour', fromAgent: true),
    ]);
    expect(cubit.state.muted, isFalse);
    expect(cubit.state.level, 0);
  });

  test('full turn: listen, transcribe, apply, speak, listen again', () async {
    final cubit = build();
    await cubit.start();
    expect(cubit.state.phase, VoicePhase.listening);
    await speak();
    expect(applied, [_turn]);
    expect(cubit.state.messages.map((m) => m.text), [
      'Bonjour',
      'date de 1998',
      'Merci. Et la toiture ?',
    ]);
    expect(cubit.state.facts, _turn.facts);
    expect(cubit.state.pending, [_turn.pending.first]);
    verify(() => player.play(any(), format: 'wav')).called(1);
    expect(cubit.state.phase, VoicePhase.listening);
    verify(
      () => agent.turn(
        propertyId: 'p1',
        step: AgentStep.technical,
        turnId: 't1',
        assetLabels: ['Calme'],
        watchPointLabels: [],
      ),
    ).called(1);
    await cubit.close();
    verify(() => recorder.dispose()).called(1);
    verify(() => player.dispose()).called(1);
  });

  test('keeps at most 34 levels', () async {
    final cubit = build();
    await cubit.start();
    for (var i = 0; i < 40; i++) {
      levels.add(-30);
    }
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.levels, hasLength(VoiceConversationState.levelCount));
    expect(cubit.state.level, 0.5);
    await cubit.close();
  });

  test('done: stops listening after the reply', () async {
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
      ),
    ).thenAnswer(
      (_) async => const AgentTurn(
        turnId: 't1',
        transcript: 'x',
        reply: 'Fini',
        done: true,
      ),
    );
    final cubit = build();
    await cubit.start();
    await cubit.finishSpeaking(); // nothing heard yet
    expect(cubit.state.error, VoiceError.empty);
    await cubit.retry();
    levels.add(-20);
    await Future<void>.delayed(Duration.zero);
    await cubit.finishSpeaking();
    expect(cubit.state.phase, VoicePhase.done);
    await cubit.close();
  });

  test('permission refused', () async {
    when(() => recorder.requestPermission()).thenAnswer((_) async => false);
    final cubit = build();
    await cubit.start();
    expect(cubit.state.error, VoiceError.permissionDenied);
    expect(cubit.state.phase, VoicePhase.idle);
    await cubit.close();
  });

  test('recorder failure', () async {
    when(() => recorder.start()).thenThrow(Exception('busy'));
    final cubit = build();
    await cubit.start();
    expect(cubit.state.error, VoiceError.permissionDenied);
    await cubit.close();
  });

  test('empty recording', () async {
    when(() => recorder.stop()).thenAnswer((_) async => null);
    final cubit = build();
    await cubit.start();
    await speak();
    expect(cubit.state.error, VoiceError.empty);
    await cubit.close();
  });

  test('transcription failures map to errors', () async {
    final cubit = build();
    for (final (failure, error) in [
      (const AgentLockedFailure(), VoiceError.locked),
      (const AgentQuotaFailure(), VoiceError.quota),
      (const AgentEmptyFailure(), VoiceError.empty),
      (const AgentTooLongFailure(), VoiceError.tooLong),
      (Exception('x'), VoiceError.network),
    ]) {
      when(
        () => agent.transcribe(
          propertyId: any(named: 'propertyId'),
          step: any(named: 'step'),
          audio: any(named: 'audio'),
          duration: any(named: 'duration'),
          format: any(named: 'format'),
        ),
      ).thenThrow(failure);
      await cubit.start();
      await speak();
      expect(cubit.state.error, error);
    }
    await cubit.close();
  });

  test('agent failure: retry with the recorded turn', () async {
    var calls = 0;
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
      ),
    ).thenAnswer((_) async {
      if (calls++ == 0) throw const AgentRequestFailure('down', 't1');
      return _turn;
    });
    final cubit = build();
    await cubit.start();
    await speak();
    expect(cubit.state.error, VoiceError.network);
    await cubit.retry();
    expect(applied, [_turn]);
    expect(cubit.state.phase, VoicePhase.listening);
    await cubit.retry(); // ignored while not idle
    await cubit.close();
  });

  test('save failure: retry applies the turn again', () async {
    applyError = Exception('save');
    final cubit = build();
    await cubit.start();
    await speak();
    expect(cubit.state.error, VoiceError.save);
    applyError = null;
    await cubit.retry();
    expect(applied, [_turn]);
    await cubit.close();
  });

  test('a speech failure is not blocking; muted skips speech', () async {
    when(() => agent.speech(any())).thenThrow(Exception('tts'));
    final cubit = build();
    await cubit.start();
    await speak();
    expect(cubit.state.phase, VoicePhase.listening);
    await cubit.toggleMute();
    expect(cubit.state.muted, isTrue);
    expect(preferences.agentMuted, isTrue);
    await speak();
    verify(() => agent.speech(any())).called(1);
    await cubit.toggleMute();
    expect(cubit.state.muted, isFalse);
    await cubit.close();
  });

  test('pause and resume', () async {
    final cubit = build();
    await cubit.pause(); // idle: nothing to stop
    await cubit.resume();
    await cubit.start();
    await cubit.pause();
    expect(cubit.state.phase, VoicePhase.paused);
    verify(() => recorder.cancel()).called(1);
    await cubit.start(); // still paused
    expect(cubit.state.phase, VoicePhase.paused);
    await cubit.resume();
    expect(cubit.state.phase, VoicePhase.listening);
    await cubit.stop();
    verify(() => player.stop()).called(1);
    await cubit.close();
  });

  test('pause while the agent speaks', () async {
    final playing = Completer<void>();
    when(() => player.play(any(), format: any(named: 'format')))
        .thenAnswer((_) => playing.future);
    final cubit = build();
    await cubit.start();
    unawaited(speak());
    for (var i = 0; i < 20 && cubit.state.phase != VoicePhase.speaking; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(cubit.state.phase, VoicePhase.speaking);
    await cubit.pause();
    verify(() => player.stop()).called(1);
    playing.complete();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(cubit.state.phase, VoicePhase.paused);
    await cubit.close();
  });

  test('the loop stops once closed', () async {
    final transcription = Completer<Transcription>();
    when(
      () => agent.transcribe(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        audio: any(named: 'audio'),
        duration: any(named: 'duration'),
        format: any(named: 'format'),
      ),
    ).thenAnswer((_) => transcription.future);
    final cubit = build();
    await cubit.start();
    unawaited(speak());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    transcription.complete(const Transcription(turnId: 't1', transcript: 'x'));
    await Future<void>.delayed(Duration.zero);
    verifyNever(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
      ),
    );
  });

  test('results arriving after stop are ignored', () async {
    final turn = Completer<AgentTurn>();
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
      ),
    ).thenAnswer((_) => turn.future);
    final cubit = build();
    await cubit.start();
    unawaited(speak());
    for (var i = 0; i < 20 && cubit.state.phase != VoicePhase.thinking; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await cubit.stop();
    turn.complete(_turn);
    await Future<void>.delayed(Duration.zero);
    expect(applied, isEmpty);
    await cubit.close();
  });

  test('a late failure after stop is ignored', () async {
    final transcription = Completer<Transcription>();
    when(
      () => agent.transcribe(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        audio: any(named: 'audio'),
        duration: any(named: 'duration'),
        format: any(named: 'format'),
      ),
    ).thenAnswer((_) => transcription.future);
    final cubit = build();
    await cubit.start();
    unawaited(speak());
    for (
      var i = 0;
      i < 20 && cubit.state.phase != VoicePhase.transcribing;
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    await cubit.stop();
    transcription.completeError(const AgentQuotaFailure());
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.error, isNull);
    final done = Completer<Transcription>();
    when(
      () => agent.transcribe(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        audio: any(named: 'audio'),
        duration: any(named: 'duration'),
        format: any(named: 'format'),
      ),
    ).thenAnswer((_) => done.future);
    await cubit.start(); // still paused: nothing listens
    await cubit.close();
  });

  test('offers the screen mode after 3 turns without answers', () async {
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
      ),
    ).thenAnswer(
      (_) async =>
          const AgentTurn(turnId: 't1', transcript: 'euh', reply: 'Pardon ?'),
    );
    final cubit = build();
    await cubit.toggleMute();
    await cubit.start();
    for (var i = 0; i < 3; i++) {
      expect(cubit.state.suggestScreenMode, isFalse);
      await speak();
    }
    expect(cubit.state.suggestScreenMode, isTrue);
    await cubit.close();
  });
}
