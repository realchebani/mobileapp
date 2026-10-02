import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/voice/models/local_voice_commands.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_form.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:voice_repository/voice_repository.dart';

part 'voice_conversation_state.dart';

/// Applies an agent turn to the step (writes through the tunnel cubit or
/// the step's form). Throwing stops the loop with [VoiceError.save].
typedef VoiceTurnHandler = Future<void> Function(AgentTurn turn);

/// The agent's lines said by the app itself (local commands, plan §5.4).
final class VoiceLocalReplies {
  const new({
    this.cancelled = '',
    this.nothingToCancel = '',
    this.confirmed = '',
    this.rejected = '',
  });

  /// "C’est annulé." after "annule".
  final String cancelled;

  /// "Il n’y a rien à annuler."
  final String nothingToCancel;

  /// "C’est noté." after "oui" to a confirmation.
  final String confirmed;

  /// "D’accord, je n’y touche pas." after "non".
  final String rejected;
}

/// The voice loop: listen → transcribe (`agent-transcribe`) → agent turn
/// (`agent-turn`) → apply ([VoiceTurnHandler]) → speak (`agent-speech`,
/// unless muted) → listen again. The microphone is off while the agent
/// speaks; a speech failure never blocks the conversation (text only).
///
/// With a [VoiceForm] (the step sheets of EPIC-14), the turns carry the
/// form's draft and entities, risky changes wait for a confirmation, "oui"
/// / "non" / "annule" / "terminé" are recognised locally, and every
/// applied answer can be undone.
class VoiceConversationCubit extends Cubit<VoiceConversationState> {
  new({
    required this._agentRepository,
    required this._recorder,
    required this._player,
    required this._preferences,
    required this._propertyId,
    required this._step,
    required String intro,
    VoiceTurnHandler? onTurn,
    VoiceForm? form,
    this._speakReplies = true,
    this._stopWhenDone = true,
    this._localReplies = const VoiceLocalReplies(),
    this._summary,
    List<String> Function()? assetLabels,
    List<String> Function()? watchPointLabels,
    DateTime Function()? clock,
    SpeechEndDetector? detector,
  }) : assert(onTurn != null || form != null, 'A turn handler is needed'),
       _onTurn = onTurn ?? form!.voiceTurnApplied,
       _form = form,
       _assetLabels = assetLabels ?? _none,
       _watchPointLabels = watchPointLabels ?? _none,
       _clock = clock ?? DateTime.now,
       _detector = detector ?? SpeechEndDetector(),
       super(
         VoiceConversationState(
           messages: [VoiceMessage(text: intro, fromAgent: true)],
           muted: _preferences.agentMuted,
           sessionStart: form?.voiceTurnCount ?? 0,
         ),
       );

  static List<String> _none() => const [];

  final AgentRepository _agentRepository;
  final VoiceRecorder _recorder;
  final VoicePlayer _player;
  final VoicePreferences _preferences;
  final String _propertyId;
  final AgentStep _step;
  final VoiceTurnHandler _onTurn;
  final VoiceForm? _form;
  final bool _speakReplies;
  final bool _stopWhenDone;
  final VoiceLocalReplies _localReplies;
  final Future<AgentTurn> Function()? _summary;
  final List<String> Function() _assetLabels;
  final List<String> Function() _watchPointLabels;
  final DateTime Function() _clock;
  final SpeechEndDetector _detector;

  StreamSubscription<double>? _levels;
  DateTime? _startedAt;
  bool _paused = false;

  /// Set by [stop] (the screen was left): late results are ignored.
  bool _stopped = false;

  /// Consecutive turns from which nothing was understood.
  int _misses = 0;

  /// After this many [_misses], the screen mode is offered.
  static const missesBeforeScreenMode = 3;

  /// A turn recorded before a failure of the agent call (retry with it).
  String? _retryTurnId;

  /// A turn whose answers could not be applied (retry applies it again).
  AgentTurn? _unapplied;

  /// Turns applied to the form in this session, oldest first.
  final List<String> _appliedTurnIds = [];

  /// Turns the seller undid, reported with the next agent call.
  final List<String> _undone = [];

  /// Asks for the microphone, then listens.
  Future<void> start() async {
    _stopped = false;
    if (!await _recorder.requestPermission()) {
      _fail(VoiceError.permissionDenied);
      return;
    }
    await _listen();
  }

  Future<void> _listen() async {
    if (isClosed) return;
    if (_paused) {
      emit(state.copyWith(phase: VoicePhase.paused));
      return;
    }
    _detector.reset();
    emit(
      state.copyWith(
        phase: VoicePhase.listening,
        levels: const [],
        error: () => null,
      ),
    );
    try {
      await _recorder.start();
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      _fail(VoiceError.permissionDenied);
      return;
    }
    _startedAt = _clock();
    await _levels?.cancel();
    _levels = _recorder.levels().listen(_onLevel);
  }

  void _onLevel(double db) {
    if (isClosed || state.phase != VoicePhase.listening) return;
    final levels = [...state.levels, normalizedLevel(db)];
    emit(
      state.copyWith(
        levels: levels.length > VoiceConversationState.levelCount
            ? levels.sublist(levels.length - VoiceConversationState.levelCount)
            : levels,
      ),
    );
    final elapsed = _clock().difference(_startedAt ?? _clock());
    if (_detector.add(db, elapsed)) unawaited(finishSpeaking());
  }

  /// "J’ai fini" (or the detected end of speech): sends the recording.
  Future<void> finishSpeaking() async {
    if (state.phase != VoicePhase.listening) return;
    emit(state.copyWith(phase: VoicePhase.transcribing));
    await _levels?.cancel();
    _levels = null;
    final heard = _detector.heardSpeech;
    final audio = await _recorder.stop();
    if (audio == null || !heard) {
      _fail(VoiceError.empty);
      return;
    }
    final Transcription transcription;
    try {
      transcription = await _agentRepository.transcribe(
        propertyId: _propertyId,
        step: _step,
        audio: audio.bytes,
        duration: audio.duration,
        format: audio.format,
      );
    } on Object catch (error) {
      _failWith(error);
      return;
    }
    if (isClosed || _stopped) return;
    emit(
      state.copyWith(
        phase: VoicePhase.thinking,
        messages: [
          ...state.messages,
          VoiceMessage(text: transcription.transcript, fromAgent: false),
        ],
      ),
    );
    if (await _local(transcription.transcript)) return;
    await _turn(transcription.turnId);
  }

  /// Handles "oui", "non", "annule", "terminé" without the agent; false
  /// when the agent must answer.
  Future<bool> _local(String transcript) async {
    if (_form == null) return false;
    final command = LocalVoiceCommand.match(transcript);
    final waiting = state.confirmations.firstOrNull;
    switch (command) {
      case LocalVoiceCommand.yes when waiting != null:
        await confirm(waiting);
      case LocalVoiceCommand.no when waiting != null:
        await reject(waiting);
      case LocalVoiceCommand.cancel:
        final undone = _appliedTurnIds.isNotEmpty;
        if (undone) undoTurn(_appliedTurnIds.last);
        _say(undone ? _localReplies.cancelled : _localReplies.nothingToCancel);
        await _listen();
      case LocalVoiceCommand.finish:
        await finish();
      case LocalVoiceCommand.yes || LocalVoiceCommand.no || null:
        return false;
    }
    return true;
  }

  void _say(String text) {
    if (isClosed || text.isEmpty) return;
    emit(
      state.copyWith(
        messages: [
          ...state.messages,
          VoiceMessage(text: text, fromAgent: true),
        ],
      ),
    );
  }

  Future<void> _turn(String turnId) async {
    final AgentTurn turn;
    final undone = [..._undone];
    try {
      turn = await _agentRepository.turn(
        propertyId: _propertyId,
        step: _step,
        turnId: turnId,
        assetLabels: _assetLabels(),
        watchPointLabels: _watchPointLabels(),
        context: _form?.voiceContext,
        undoneTurnIds: undone,
      );
    } on Object catch (error) {
      _retryTurnId = switch (error) {
        AgentRequestFailure() => turnId,
        _ => null,
      };
      _failWith(error);
      return;
    }
    _undone.removeWhere(undone.contains);
    _retryTurnId = null;
    // The screen was left meanwhile: nothing is applied any more.
    if (isClosed || _stopped) return;
    await _apply(turn);
  }

  /// The pills of [turn] applied to the form.
  static List<VoiceAppliedPill> _pillsOf(AgentTurn turn) => [
    for (final fact in turn.facts)
      VoiceAppliedPill(
        turnId: turn.turnId,
        key: fact.field,
        label: fact.label,
        changedLabel: fact.changedLabel,
      ),
    for (final (i, op) in turn.entityOps.indexed)
      VoiceAppliedPill(
        turnId: turn.turnId,
        key: 'op:$i',
        label: op.label,
        changedLabel: op.changedLabel,
      ),
  ];

  Future<void> _apply(AgentTurn turn) async {
    try {
      await _onTurn(turn);
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      _unapplied = turn;
      _fail(VoiceError.save);
      return;
    }
    _unapplied = null;
    if (isClosed) return;
    _misses = turn.understood ? 0 : _misses + 1;
    final facts = {
      for (final fact in state.facts) fact.field: fact,
      for (final fact in turn.facts) fact.field: fact,
    };
    if (_form != null) _appliedTurnIds.add(turn.turnId);
    final outOfStep = {
      for (final item in state.outOfStep) item.field: item,
      for (final item in turn.outOfStep) item.field: item,
    };
    emit(
      state.copyWith(
        phase: VoicePhase.speaking,
        messages: [
          ...state.messages,
          VoiceMessage(text: turn.reply, fromAgent: true),
        ],
        facts: facts.values.toList(),
        pending: [
          for (final pill in turn.pending)
            if (!facts.containsKey(pill.field)) pill,
        ],
        suggestScreenMode: _misses >= missesBeforeScreenMode,
        applied: _form == null
            ? state.applied
            : [...state.applied, ..._pillsOf(turn)],
        confirmations: [
          ...state.confirmations,
          for (final confirmation in turn.confirmations)
            VoicePendingConfirmation(
              turnId: turn.turnId,
              confirmation: confirmation,
            ),
        ],
        outOfStep: outOfStep.values.toList(),
        turnIds: [..._appliedTurnIds],
      ),
    );
    if (_speakReplies) await _speak(turn.turnId);
    if (isClosed) return;
    if (turn.done && _stopWhenDone) {
      emit(state.copyWith(phase: VoicePhase.done));
      return;
    }
    await _listen();
  }

  /// "Oui" to [item] (tapped or said): its change is applied as a turn of
  /// its own (undoable like the others).
  Future<void> confirm(VoicePendingConfirmation item) async {
    if (isClosed || !state.confirmations.contains(item)) return;
    emit(
      state.copyWith(
        confirmations: [
          for (final other in state.confirmations)
            if (other != item) other,
        ],
      ),
    );
    if (item.isSummary) {
      await _stopListening();
      emit(state.copyWith(phase: VoicePhase.done, finished: true));
      return;
    }
    final turn = AgentTurn.confirmed(item.turnId, item.confirmation);
    try {
      await _onTurn(turn);
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      _fail(VoiceError.save);
      return;
    }
    if (isClosed) return;
    _appliedTurnIds.add(turn.turnId);
    emit(
      state.copyWith(
        applied: [...state.applied, ..._pillsOf(turn)],
        turnIds: [..._appliedTurnIds],
      ),
    );
    _say(_localReplies.confirmed);
    if (state.phase != VoicePhase.listening) await _listen();
  }

  /// "Non" to [item]: nothing changes (the summary resumes the dictation).
  Future<void> reject(VoicePendingConfirmation item) async {
    if (isClosed || !state.confirmations.contains(item)) return;
    emit(
      state.copyWith(
        confirmations: [
          for (final other in state.confirmations)
            if (other != item) other,
        ],
      ),
    );
    _say(_localReplies.rejected);
    if (state.phase != VoicePhase.listening) await _listen();
  }

  /// "Annuler ce tour": restores the form as before [turnId].
  void undoTurn(String turnId) {
    final form = _form;
    if (form == null || isClosed) return;
    form.undoVoiceTurn(turnId);
    _appliedTurnIds.remove(turnId);
    _reportUndone(turnId);
    emit(
      state.copyWith(
        applied: [
          for (final pill in state.applied)
            if (pill.turnId != turnId) pill,
        ],
        turnIds: [..._appliedTurnIds],
      ),
    );
  }

  /// The "Annuler" cross of [pill]: that answer only.
  void undoPill(VoiceAppliedPill pill) {
    final form = _form;
    if (form == null || isClosed) return;
    form.undoVoicePill(pill.turnId, pill.key);
    _reportUndone(pill.turnId);
    final remaining = [
      for (final other in state.applied)
        if (other != pill) other,
    ];
    // An entity operation removed: the later ones of that turn shift.
    if (pill.key.startsWith('op:')) {
      final index = int.parse(pill.key.substring(3));
      for (final (i, other) in remaining.indexed) {
        if (other.turnId != pill.turnId || !other.key.startsWith('op:')) {
          continue;
        }
        final otherIndex = int.parse(other.key.substring(3));
        if (otherIndex > index) {
          remaining[i] = VoiceAppliedPill(
            turnId: other.turnId,
            key: 'op:${otherIndex - 1}',
            label: other.label,
            changedLabel: other.changedLabel,
          );
        }
      }
    }
    emit(state.copyWith(applied: remaining));
  }

  void _reportUndone(String turnId) {
    // A confirmed change ("t1#c1") belongs to its agent turn.
    final id = turnId.split('#').first;
    if (!_undone.contains(id)) _undone.add(id);
  }

  /// "Terminer" / "terminé": the rooms dictation asks the spoken summary
  /// first ("9 pièces pour 115 m² habitables. Est-ce correct ?"); the
  /// other sheets end at once.
  Future<void> finish() async {
    final summary = _summary;
    await _stopListening();
    if (summary == null || isClosed) {
      if (!isClosed) {
        emit(state.copyWith(phase: VoicePhase.done, finished: true));
      }
      return;
    }
    emit(state.copyWith(phase: VoicePhase.thinking));
    final AgentTurn turn;
    try {
      turn = await summary();
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(phase: VoicePhase.done, finished: true));
      return;
    }
    if (isClosed || _stopped) return;
    emit(
      state.copyWith(
        phase: VoicePhase.speaking,
        messages: [
          ...state.messages,
          VoiceMessage(text: turn.reply, fromAgent: true),
        ],
        confirmations: [
          ...state.confirmations,
          VoicePendingConfirmation(
            turnId: turn.turnId,
            confirmation: AgentConfirmation(
              id: VoicePendingConfirmation.summaryId,
              reason: AgentConfirmationReason.mediumConfidence,
              label: turn.reply,
            ),
          ),
        ],
      ),
    );
    await _speak(turn.turnId);
    await _listen();
  }

  Future<void> _stopListening() async {
    if (state.phase != VoicePhase.listening) return;
    final levels = _levels;
    _levels = null;
    unawaited(levels?.cancel());
    await _recorder.cancel();
  }

  Future<void> _speak(String turnId) async {
    if (state.muted || _paused) return;
    try {
      final speech = await _agentRepository.speech(turnId);
      if (isClosed || state.muted || _paused) return;
      await _player.play(speech.bytes, format: speech.format);
    } on Object catch (error, stackTrace) {
      // The reply stays displayed: a voice failure is never blocking.
      addError(error, stackTrace);
    }
  }

  void _failWith(Object error) {
    if (_stopped) return;
    _fail(_errorOf(error));
  }

  static VoiceError _errorOf(Object error) => switch (error) {
    AgentLockedFailure() => VoiceError.locked,
    AgentQuotaFailure() => VoiceError.quota,
    AgentEmptyFailure() => VoiceError.empty,
    AgentTooLongFailure() => VoiceError.tooLong,
    _ => VoiceError.network,
  };

  void _fail(VoiceError error) {
    if (isClosed) return;
    emit(state.copyWith(phase: VoicePhase.idle, error: () => error));
  }

  /// "Réessayer" after an error.
  Future<void> retry() async {
    if (state.phase != VoicePhase.idle) return;
    final unapplied = _unapplied;
    final turnId = _retryTurnId;
    if (unapplied != null) {
      emit(state.copyWith(phase: VoicePhase.thinking, error: () => null));
      await _apply(unapplied);
    } else if (turnId != null) {
      emit(state.copyWith(phase: VoicePhase.thinking, error: () => null));
      await _turn(turnId);
    } else {
      await start();
    }
  }

  /// Pauses: stops listening (nothing is sent) or speaking.
  Future<void> pause() async {
    _paused = true;
    if (state.phase == VoicePhase.listening) {
      await _levels?.cancel();
      _levels = null;
      await _recorder.cancel();
      emit(state.copyWith(phase: VoicePhase.paused));
    } else if (state.phase == VoicePhase.speaking) {
      await _player.stop();
    }
  }

  /// Resumes listening after [pause].
  Future<void> resume() async {
    _paused = false;
    if (state.phase == VoicePhase.paused) await _listen();
  }

  /// Mutes or unmutes the agent's voice (remembered on the device).
  Future<void> toggleMute() async {
    final muted = !state.muted;
    emit(state.copyWith(muted: muted));
    if (muted) await _player.stop();
    await _preferences.setAgentMuted(muted: muted);
  }

  /// Stops listening and speaking (leaving the screen); the undone turns
  /// not reported yet are sent (quality follow-up, best effort).
  Future<void> stop() async {
    _paused = true;
    _stopped = true;
    await _levels?.cancel();
    _levels = null;
    await _recorder.cancel();
    await _player.stop();
    reportUndone(_undone);
    _undone.clear();
  }

  /// Reports [turnIds] as undone (e.g. the whole session, undone from the
  /// snackbar once the sheet is closed); failures are ignored.
  void reportUndone(List<String> turnIds) {
    final ids = {for (final id in turnIds) id.split('#').first}.toList();
    if (ids.isEmpty) return;
    unawaited(
      _agentRepository
          .markUndone(propertyId: _propertyId, step: _step, turnIds: ids)
          .catchError((Object _) {}),
    );
  }

  @override
  Future<void> close() async {
    await _levels?.cancel();
    await _recorder.dispose();
    await _player.dispose();
    await super.close();
  }
}
