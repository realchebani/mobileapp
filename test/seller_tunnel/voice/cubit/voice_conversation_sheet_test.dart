import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_repository/voice_repository.dart';

import '../../../helpers/helpers.dart';

/// A step form recording what the conversation asks.
class _Form implements VoiceForm {
  final applied = <AgentTurn>[];
  final undoneTurns = <String>[];
  final undonePills = <(String, String)>[];
  int undoneFrom = -1;
  Exception? applyError;

  @override
  Future<void> voiceTurnApplied(AgentTurn turn) async {
    if (applyError case final error?) throw error;
    applied.add(turn);
  }

  @override
  void undoVoiceTurn(String turnId) => undoneTurns.add(turnId);

  @override
  void undoVoicePill(String turnId, String key) =>
      undonePills.add((turnId, key));

  @override
  int get voiceTurnCount => 3;

  @override
  void undoVoiceTurnsFrom(int index) => undoneFrom = index;

  @override
  AgentTurnContext get voiceContext =>
      const AgentTurnContext(draft: {'purchase_year': 2010});
}

const _confirmation = AgentConfirmation(
  id: 'c1',
  reason: AgentConfirmationReason.typeChange,
  label: 'Type : garage ?',
  patch: {'property_type': 'stationnement'},
);

const _turn = AgentTurn(
  turnId: 't1',
  transcript: 'achetée en 2012',
  reply: 'Noté.',
  patch: {'purchase_year': 2012},
  facts: [
    AgentPill(
      field: 'purchase_year',
      label: 'Achat 2012',
      changedLabel: 'Modifié : 2010 → 2012',
    ),
  ],
  entityOps: [
    AgentEntityChange(
      entity: AgentEntity.room,
      op: AgentEntityOp.create,
      target: 'new',
      label: 'Séjour',
    ),
    AgentEntityChange(
      entity: AgentEntity.room,
      op: AgentEntityOp.create,
      target: 'new',
      label: 'Cuisine',
    ),
  ],
  confirmations: [_confirmation],
  outOfStep: [
    AgentOutOfStep(
      field: 'construction_year',
      step: 'technical',
      label: 'Construction → Technique',
    ),
  ],
);

void main() {
  late MockAgentRepository agent;
  late MockVoiceRecorder recorder;
  late MockVoicePlayer player;
  late VoicePreferences preferences;
  late StreamController<double> levels;
  late _Form form;
  late List<String> transcripts;
  late DateTime now;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AgentStep.context);
    registerFallbackValue(const AgentTurnContext());
  });

  void answerTurn(AgentTurn turn) => when(
    () => agent.turn(
      propertyId: any(named: 'propertyId'),
      step: any(named: 'step'),
      turnId: any(named: 'turnId'),
      assetLabels: any(named: 'assetLabels'),
      watchPointLabels: any(named: 'watchPointLabels'),
      context: any(named: 'context'),
      undoneTurnIds: any(named: 'undoneTurnIds'),
    ),
  ).thenAnswer((_) async => turn);

  setUp(() async {
    agent = MockAgentRepository();
    recorder = MockVoiceRecorder();
    player = MockVoicePlayer();
    preferences = (await testVoiceServices()).preferences!;
    levels = StreamController<double>.broadcast();
    form = _Form();
    transcripts = ['achetée en 2012'];
    now = DateTime(2026, 10, 2, 10);
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
    var count = 0;
    when(
      () => agent.transcribe(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        audio: any(named: 'audio'),
        duration: any(named: 'duration'),
        format: any(named: 'format'),
      ),
    ).thenAnswer(
      (_) async => Transcription(
        turnId: 't${++count}',
        transcript: transcripts[(count - 1).clamp(0, transcripts.length - 1)],
      ),
    );
    answerTurn(_turn);
    when(() => agent.speech(any())).thenAnswer(
      (_) async => AgentSpeech(bytes: Uint8List.fromList([2]), format: 'wav'),
    );
    when(
      () => agent.markUndone(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnIds: any(named: 'turnIds'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => agent.roomsSummary(
        propertyId: any(named: 'propertyId'),
        rooms: any(named: 'rooms'),
      ),
    ).thenAnswer(
      (_) async => const AgentTurn(
        turnId: 'ts',
        transcript: '',
        reply: 'J’ai noté 2 pièces. Est-ce correct ?',
      ),
    );
  });

  tearDown(() => levels.close());

  VoiceConversationCubit build({
    bool speakReplies = true,
    bool stopWhenDone = true,
    Future<AgentTurn> Function()? summary,
  }) => VoiceConversationCubit(
    agentRepository: agent,
    recorder: recorder,
    player: player,
    preferences: preferences,
    propertyId: 'p1',
    step: AgentStep.context,
    intro: 'Bonjour',
    form: form,
    speakReplies: speakReplies,
    stopWhenDone: stopWhenDone,
    summary: summary,
    localReplies: const VoiceLocalReplies(
      cancelled: 'Annulé.',
      nothingToCancel: 'Rien à annuler.',
      confirmed: 'Noté !',
      rejected: 'Je n’y touche pas.',
    ),
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

  test('a turn carries the form context; pills, confirmations, '
      'elsewhere', () async {
    final cubit = build();
    expect(cubit.state.sessionStart, 3);
    await cubit.start();
    await speak();
    expect(form.applied, [_turn]);
    expect(cubit.state.applied, const [
      VoiceAppliedPill(
        turnId: 't1',
        key: 'purchase_year',
        label: 'Achat 2012',
        changedLabel: 'Modifié : 2010 → 2012',
      ),
      VoiceAppliedPill(turnId: 't1', key: 'op:0', label: 'Séjour'),
      VoiceAppliedPill(turnId: 't1', key: 'op:1', label: 'Cuisine'),
    ]);
    expect(cubit.state.confirmations, const [
      VoicePendingConfirmation(turnId: 't1', confirmation: _confirmation),
    ]);
    expect(cubit.state.outOfStep, _turn.outOfStep);
    expect(cubit.state.appliedTurns, 1);
    expect(cubit.state.turnIds, ['t1']);
    verify(
      () => agent.turn(
        propertyId: 'p1',
        step: AgentStep.context,
        turnId: 't1',
        assetLabels: [],
        watchPointLabels: [],
        context: const AgentTurnContext(draft: {'purchase_year': 2010}),
        undoneTurnIds: [],
      ),
    ).called(1);
    await cubit.close();
  });

  test('"oui" confirms locally, "non" rejects, else the agent', () async {
    transcripts = ['achetée en 2012', 'Oui.', 'non', 'oui'];
    final cubit = build();
    await cubit.start();
    await speak();
    await speak(); // "Oui." → the type change is applied
    expect(form.applied.last.turnId, 't1#c1');
    expect(form.applied.last.patch, {'property_type': 'stationnement'});
    expect(cubit.state.applied.last.label, 'Type : garage');
    expect(cubit.state.messages.last.text, 'Noté !');
    expect(cubit.state.confirmations, isEmpty);
    expect(cubit.state.phase, VoicePhase.listening);
    // "non" without a confirmation waiting: the agent answers.
    answerTurn(
      const AgentTurn(
        turnId: 't3',
        transcript: 'non',
        reply: 'D’accord.',
        confirmations: [_confirmation],
      ),
    );
    await speak();
    expect(cubit.state.messages.last.text, 'D’accord.');
    expect(cubit.state.confirmations, hasLength(1));
    await speak(); // "oui" again
    expect(form.applied.last.turnId, 't3#c1');
    await cubit.close();
  });

  test('"non" rejects a waiting confirmation locally', () async {
    transcripts = ['achetée en 2012', 'Non merci'];
    final cubit = build();
    await cubit.start();
    await speak();
    await speak();
    expect(cubit.state.confirmations, isEmpty);
    expect(cubit.state.messages.last.text, 'Je n’y touche pas.');
    expect(form.applied, hasLength(1));
    await cubit.close();
  });

  test('tapped confirmations; a failed apply is a save error', () async {
    final cubit = build();
    await cubit.start();
    await speak();
    final waiting = cubit.state.confirmations.single;
    await cubit.reject(waiting);
    expect(cubit.state.confirmations, isEmpty);
    expect(cubit.state.messages.last.text, 'Je n’y touche pas.');
    await cubit.reject(waiting); // already answered
    await cubit.confirm(waiting); // already answered
    expect(form.applied, hasLength(1));
    // Again, with a failing form.
    answerTurn(_turn);
    await speak();
    form.applyError = Exception('busy');
    await cubit.confirm(cubit.state.confirmations.single);
    expect(cubit.state.error, VoiceError.save);
    await cubit.close();
  });

  test('"annule" undoes the last turn; nothing to undo', () async {
    transcripts = ['Annule', 'achetée en 2012', 'efface ça'];
    final cubit = build();
    await cubit.start();
    await speak();
    expect(cubit.state.messages.last.text, 'Rien à annuler.');
    await speak();
    await speak();
    // The agent's turn id (the answer of the second recording).
    expect(form.undoneTurns, ['t1']);
    expect(cubit.state.messages.last.text, 'Annulé.');
    expect(cubit.state.applied, isEmpty);
    expect(cubit.state.appliedTurns, 0);
    // The undone turn is reported with the next agent call.
    transcripts = ['x'];
    await speak();
    verify(
      () => agent.turn(
        propertyId: 'p1',
        step: AgentStep.context,
        turnId: any(named: 'turnId'),
        assetLabels: [],
        watchPointLabels: [],
        context: any(named: 'context'),
        undoneTurnIds: ['t1'],
      ),
    ).called(1);
    await cubit.close();
  });

  test('undo a pill: later entity pills of the turn shift', () async {
    final cubit = build();
    await cubit.start();
    await speak();
    cubit.undoPill(cubit.state.applied[1]);
    expect(form.undonePills, [('t1', 'op:0')]);
    expect(cubit.state.applied.map((p) => p.key), ['purchase_year', 'op:0']);
    expect(cubit.state.applied.last.label, 'Cuisine');
    cubit.undoPill(cubit.state.applied.first);
    expect(cubit.state.applied.map((p) => p.key), ['op:0']);
    await cubit.stop();
    verify(
      () => agent.markUndone(
        propertyId: 'p1',
        step: AgentStep.context,
        turnIds: ['t1'],
      ),
    ).called(1);
    cubit
      ..reportUndone(const [])
      ..reportUndone(const ['t1#c1', 't1']);
    verify(
      () => agent.markUndone(
        propertyId: 'p1',
        step: AgentStep.context,
        turnIds: ['t1'],
      ),
    ).called(1);
    await cubit.close();
    cubit
      ..undoTurn('t1')
      ..undoPill(const VoiceAppliedPill(turnId: 't', key: 'k', label: 'l'));
    expect(form.undoneTurns, isEmpty);
  });

  test('"terminé" ends the sheet', () async {
    transcripts = ['C’est tout.'];
    final cubit = build();
    await cubit.start();
    await speak();
    expect(cubit.state.finished, isTrue);
    expect(cubit.state.phase, VoicePhase.done);
    await cubit.close();
  });

  test('rooms dictation: silent, keeps listening, spoken summary', () async {
    answerTurn(
      const AgentTurn(
        turnId: 't1',
        transcript: 'x',
        reply: 'Séjour noté.',
        done: true,
      ),
    );
    var summaries = 0;
    final cubit = build(
      speakReplies: false,
      stopWhenDone: false,
      summary: () {
        summaries++;
        return agent.roomsSummary(propertyId: 'p1', rooms: const []);
      },
    );
    await cubit.start();
    await speak();
    verifyNever(() => agent.speech(any()));
    expect(cubit.state.phase, VoicePhase.listening);
    await cubit.finish();
    expect(summaries, 1);
    verify(() => agent.speech('ts')).called(1);
    expect(
      cubit.state.messages.last.text,
      'J’ai noté 2 pièces. Est-ce correct ?',
    );
    final summary = cubit.state.confirmations.single;
    expect(summary.isSummary, isTrue);
    expect(summary.confirmation.label, isEmpty);
    // Never listening again after "Terminer": Oui / Non are tapped.
    expect(cubit.state.phase, VoicePhase.idle);
    // "non": the dictation goes on.
    await cubit.reject(summary);
    expect(cubit.state.finished, isFalse);
    expect(cubit.state.phase, VoicePhase.listening);
    // "oui" to a new summary ends it.
    await cubit.finish();
    await cubit.confirm(cubit.state.confirmations.single);
    expect(cubit.state.finished, isTrue);
    await cubit.close();
  });

  test('a summary failure ends the sheet anyway', () async {
    final cubit = build(summary: () async => throw Exception('down'));
    await cubit.start();
    await cubit.finish();
    expect(cubit.state.finished, isTrue);
    await cubit.close();
    await cubit.finish();
  });

  test('a summary answered after closing is ignored', () async {
    final done = Completer<AgentTurn>();
    final cubit = build(summary: () => done.future);
    await cubit.start();
    final finishing = cubit.finish();
    await cubit.stop();
    done.complete(const AgentTurn(turnId: 'ts', transcript: '', reply: 'x'));
    await finishing;
    expect(cubit.state.confirmations, isEmpty);
    await cubit.close();
  });

  test('the summary of a closed cubit is ignored', () async {
    final done = Completer<AgentTurn>();
    final cubit = build(summary: () => done.future);
    await cubit.start();
    final finishing = cubit.finish();
    await cubit.close();
    done.completeError(Exception('late'));
    await finishing;
  });

  test('a new turn replaces the pending questions; "oui" answers the '
      'latest', () async {
    transcripts = ['achetée en 2012', 'en fait un box', 'oui'];
    final cubit = build();
    await cubit.start();
    await speak();
    const latest = AgentConfirmation(
      id: 'c1',
      reason: AgentConfirmationReason.mediumConfidence,
      label: 'Stationnement box ?',
      patch: {'parking_kind': 'box'},
    );
    answerTurn(
      const AgentTurn(
        turnId: 't2',
        transcript: 'en fait un box',
        reply: 'Un box ?',
        confirmations: [latest],
      ),
    );
    await speak();
    expect(cubit.state.confirmations, const [
      VoicePendingConfirmation(turnId: 't2', confirmation: latest),
    ]);
    await speak(); // "oui"
    expect(form.applied.last.patch, {'parking_kind': 'box'});
    await cubit.close();
  });

  test('"Terminer" during a turn: the turn is applied, then the sheet '
      'ends without listening again', () async {
    final answer = Completer<AgentTurn>();
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
        context: any(named: 'context'),
        undoneTurnIds: any(named: 'undoneTurnIds'),
      ),
    ).thenAnswer((_) => answer.future);
    final cubit = build();
    await cubit.start();
    unawaited(speak());
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(cubit.state.phase, VoicePhase.thinking);
    await cubit.finish();
    await cubit.finish(); // once
    expect(cubit.state.finished, isFalse);
    answer.complete(_turn);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(form.applied, [_turn]);
    expect(cubit.state.finished, isTrue);
    verify(() => recorder.start()).called(1);
    await cubit.close();
  });

  test('"Terminer" during a failing turn ends the sheet', () async {
    final answer = Completer<AgentTurn>();
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
        context: any(named: 'context'),
        undoneTurnIds: any(named: 'undoneTurnIds'),
      ),
    ).thenAnswer((_) => answer.future);
    final cubit = build();
    await cubit.start();
    unawaited(speak());
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await cubit.finish();
    answer.completeError(Exception('down'));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(cubit.state.finished, isTrue);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });
}
