import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_repository/voice_repository.dart';

import '../../../helpers/helpers.dart';

/// EPIC-16: what the sheet does with the values said for other steps.

/// A step form recording what the conversation asks.
class _Form implements VoiceForm {
  final applied = <AgentTurn>[];
  final undoneTurns = <String>[];
  final undonePills = <(String, String)>[];
  int undoneFrom = -1;
  Exception? applyError;
  bool prefilled = false;

  @override
  bool confirmPrefilled() {
    final had = prefilled;
    prefilled = false;
    return had;
  }

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

/// The tunnel's side: what the sheet asks it.
class _Sink implements VoicePendingSink {
  final recorded = <(List<AgentCrossStep>, List<String>)>[];
  final accepted = <String>[];
  final rejected = <(String, bool)>[];
  bool saves = true;

  @override
  void pendingRecorded(
    List<AgentCrossStep> items,
    List<String> supersededIds,
  ) => recorded.add((items, supersededIds));

  @override
  bool isStepValidated(AgentStep step) => step == AgentStep.context;

  @override
  Future<bool> acceptPendingUpdate(String id) async {
    accepted.add(id);
    return saves;
  }

  @override
  Future<void> rejectPending(String id, {required bool cancelled}) async =>
      rejected.add((id, cancelled));
}

const _price = AgentCrossStep(
  id: 'p1',
  targetStep: AgentStep.context,
  kind: AgentCrossStepKind.field,
  field: 'purchase_price_eur',
  value: 320000,
  label: 'Prix 320 000 €',
  changedLabel: 'Prix : 300 000 € → 320 000 €',
);
const _year = AgentCrossStep(
  id: 'p2',
  targetStep: AgentStep.technical,
  kind: AgentCrossStepKind.field,
  field: 'construction_year',
  value: 1998,
  label: 'Construction 1998',
);
const _room = AgentCrossStep(
  id: 'p3',
  targetStep: AgentStep.context,
  kind: AgentCrossStepKind.room,
  label: 'Cuisine',
);

const _turn = AgentTurn(
  turnId: 't1',
  transcript: 'x',
  reply: 'Noté.',
  notes: ['Vendu meublé', 'Grenier'],
  crossStep: [_price, _year, _room],
  supersededIds: ['p0'],
);

void main() {
  late MockAgentRepository agent;
  late MockVoiceRecorder recorder;
  late MockVoicePlayer player;
  late VoicePreferences preferences;
  late StreamController<double> levels;
  late _Form form;
  late _Sink sink;
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
    sink = _Sink();
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
    pendingSink: sink,
    updateLabel: (item) => 'MAJ ${item.label}',
    speakReplies: speakReplies,
    stopWhenDone: stopWhenDone,
    summary: summary,
    localReplies: const VoiceLocalReplies(
      cancelled: 'Annulé.',
      nothingToCancel: 'Rien à annuler.',
      confirmed: 'Noté !',
      rejected: 'Je n’y touche pas.',
      prefilledConfirmed: 'Confirmé.',
      notePrefix: 'Note : ',
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

  test(
    'values for other steps: pills, updates of validated steps, notes',
    () async {
      final cubit = build();
      await cubit.start();
      await speak();
      expect(sink.recorded.single.$1, _turn.crossStep);
      expect(sink.recorded.single.$2, ['p0']);
      expect(cubit.state.crossStep, const [
        VoiceCrossPill(turnId: 't1', item: _price),
        VoiceCrossPill(turnId: 't1', item: _year),
        VoiceCrossPill(turnId: 't1', item: _room),
      ]);
      // Only the field of the validated step (not the entity) asks.
      expect(cubit.state.confirmations.single.updateOf, 'p1');
      expect(
        cubit.state.confirmations.single.confirmation.label,
        'MAJ Prix 320 000 €',
      );
      expect(cubit.state.applied.map((p) => (p.key, p.label)), [
        ('note:0', 'Note : Vendu meublé'),
        ('note:1', 'Note : Grenier'),
      ]);
      // A later turn superseding a pill removes it.
      answerTurn(
        const AgentTurn(
          turnId: 't2',
          transcript: '',
          reply: '',
          supersededIds: ['p2'],
        ),
      );
      await speak();
      expect(cubit.state.crossStep.map((p) => p.item.id), ['p1', 'p3']);
      expect(
        const VoiceCrossPill(turnId: 't', item: _room).props,
        hasLength(2),
      );
      await cubit.close();
    },
  );

  test('« oui » to an update saves it; a failed save stops', () async {
    transcripts = ['x', 'oui'];
    final cubit = build();
    await cubit.start();
    await speak();
    await speak();
    expect(sink.accepted, ['p1']);
    expect(cubit.state.messages.last.text, 'Noté !');
    expect(cubit.state.confirmations, isEmpty);
    await cubit.close();

    sink = _Sink()..saves = false;
    transcripts = ['x'];
    final failing = build();
    await failing.start();
    await speak();
    await failing.confirm(failing.state.confirmations.single);
    expect(failing.state.error, VoiceError.save);
    await failing.close();
  });

  test('« non » to an update rejects it', () async {
    final cubit = build();
    await cubit.start();
    await speak();
    await cubit.reject(cubit.state.confirmations.single);
    expect(sink.rejected, [('p1', false)]);
    expect(cubit.state.messages.last.text, 'Je n’y touche pas.');
    await cubit.close();
  });

  test('the cross of a « Noté pour » pill drops it and its update', () async {
    final cubit = build();
    await cubit.start();
    await speak();
    cubit.undoCross(cubit.state.crossStep.first);
    expect(sink.rejected, [('p1', true)]);
    expect(cubit.state.crossStep.map((p) => p.item.id), ['p2', 'p3']);
    expect(cubit.state.confirmations, isEmpty);
    // Already gone: nothing more.
    cubit.undoCross(const VoiceCrossPill(turnId: 't1', item: _price));
    expect(sink.rejected, hasLength(1));
    await cubit.stop();
    verify(
      () => agent.markUndone(
        propertyId: 'p1',
        step: AgentStep.context,
        turnIds: ['t1'],
      ),
    ).called(1);
    await cubit.close();
  });

  test('a note pill undone shifts the next ones', () async {
    final cubit = build();
    await cubit.start();
    await speak();
    cubit.undoPill(cubit.state.applied.first);
    expect(form.undonePills, [('t1', 'note:0')]);
    expect(cubit.state.applied.map((p) => p.key), ['note:0']);
    await cubit.close();
  });

  test(
    '« oui » with nothing to answer confirms the pre-filled values',
    () async {
      answerTurn(const AgentTurn(turnId: 't1', transcript: '', reply: 'Noté.'));
      transcripts = ['x', 'oui', 'oui'];
      form.prefilled = true;
      final cubit = build();
      await cubit.start();
      await speak();
      await speak();
      expect(cubit.state.messages.last.text, 'Confirmé.');
      expect(cubit.state.phase, VoicePhase.listening);
      // Nothing left to confirm: the agent answers.
      await speak();
      expect(cubit.state.messages.last.text, 'Noté.');
      await cubit.close();
    },
  );

  test('a refused quota, network or microphone is remembered', () async {
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
    ).thenThrow(const AgentQuotaFailure(120));
    final cubit = build();
    await cubit.start();
    await speak();
    await Future<void>.delayed(Duration.zero);
    expect(preferences.quotaReached(now), isTrue);
    await cubit.close();

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
    ).thenThrow(const AgentRequestFailure());
    final offline = build();
    await offline.start();
    await speak();
    await Future<void>.delayed(Duration.zero);
    expect(
      preferences.recentlyOffline(now, const Duration(minutes: 1)),
      isTrue,
    );
    await offline.close();

    when(() => recorder.requestPermission()).thenAnswer((_) async => false);
    final denied = build();
    await denied.start();
    await Future<void>.delayed(Duration.zero);
    expect(preferences.micDenied, isTrue);
    await denied.close();
    when(() => recorder.requestPermission()).thenAnswer((_) async => true);
    final granted = build();
    await granted.start();
    await Future<void>.delayed(Duration.zero);
    expect(preferences.micDenied, isFalse);
    await granted.close();
  });
}
