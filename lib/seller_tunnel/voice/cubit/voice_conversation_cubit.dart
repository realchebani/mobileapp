import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/voice/models/local_voice_commands.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_defaults.dart';
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
    this.prefilledConfirmed = '',
    this.notePrefix = '',
  });

  /// "C’est annulé." after "annule".
  final String cancelled;

  /// "Il n’y a rien à annuler."
  final String nothingToCancel;

  /// "C’est noté." after "oui" to a confirmation.
  final String confirmed;

  /// "D’accord, je n’y touche pas." after "non".
  final String rejected;

  /// "C’est confirmé." after "oui" to the pre-filled values (EPIC-16).
  final String prefilledConfirmed;

  /// "Note : " before a note in its pill (EPIC-16).
  final String notePrefix;
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
    this._pendingSink,
    this._updateLabel,
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
  final VoicePendingSink? _pendingSink;
  final String Function(AgentCrossStep item)? _updateLabel;
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

  /// "Terminer" was asked: no more listening; the turn in flight is
  /// applied first.
  bool _finishing = false;

  /// A recording is being transcribed, answered or applied.
  bool _inFlight = false;

  /// Turns the seller undid, reported with the next agent call.
  final List<String> _undone = [];

  /// Asks for the microphone, then listens.
  Future<void> start() async {
    _stopped = false;
    if (!await _recorder.requestPermission()) {
      _fail(VoiceError.permissionDenied);
      return;
    }
    if (_preferences.micDenied) {
      unawaited(_preferences.setMicDenied(denied: false));
    }
    await _listen();
  }

  Future<void> _listen() async {
    if (isClosed || _finishing) return;
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
    _inFlight = true;
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
    // The latest question asked (older ones were dropped).
    final waiting = state.confirmations.lastOrNull;
    switch (command) {
      case LocalVoiceCommand.yes when waiting != null:
        _inFlight = false;
        await confirm(waiting);
      case LocalVoiceCommand.no when waiting != null:
        _inFlight = false;
        await reject(waiting);
      case LocalVoiceCommand.cancel:
        _inFlight = false;
        final undone = _appliedTurnIds.isNotEmpty;
        if (undone) undoTurn(_appliedTurnIds.last);
        _say(undone ? _localReplies.cancelled : _localReplies.nothingToCancel);
        await _listen();
      case LocalVoiceCommand.finish:
        _inFlight = false;
        await finish();
      // EPIC-16: "oui" with no question waiting confirms the values
      // pre-filled « À confirmer » on the step, without the agent.
      case LocalVoiceCommand.yes when _form.confirmPrefilled():
        _inFlight = false;
        _say(_localReplies.prefilledConfirmed);
        await _listen();
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

  List<VoiceAppliedPill> _notePillsOf(AgentTurn turn) => [
    for (final (i, note) in turn.notes.indexed)
      VoiceAppliedPill(
        turnId: turn.turnId,
        key: 'note:$i',
        label: '${_localReplies.notePrefix}$note',
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
    // EPIC-16: what was said for other steps is kept by the tunnel; a
    // value for a validated step is proposed as an update.
    final sink = _pendingSink;
    sink?.pendingRecorded(turn.crossStep, turn.supersededIds);
    final superseded = {...turn.supersededIds};
    final updates = [
      if (sink != null && VoiceDefaults.updateValidatedSteps)
        for (final item in turn.crossStep)
          if ((item.kind == AgentCrossStepKind.field ||
                  item.kind == AgentCrossStepKind.note) &&
              sink.isStepValidated(item.targetStep))
            VoicePendingConfirmation(
              turnId: turn.turnId,
              confirmation: AgentConfirmation(
                id: '${VoicePendingConfirmation.updatePrefix}${item.id}',
                reason: AgentConfirmationReason.strongChange,
                label: _updateLabel?.call(item) ?? item.label,
              ),
            ),
    ];
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
            : [...state.applied, ..._pillsOf(turn), ..._notePillsOf(turn)],
        // Only the questions of the latest turn are pending: a spoken
        // "oui" answers the last one asked.
        confirmations: [
          for (final confirmation in turn.confirmations)
            VoicePendingConfirmation(
              turnId: turn.turnId,
              confirmation: confirmation,
            ),
          ...updates,
        ],
        outOfStep: outOfStep.values.toList(),
        crossStep: [
          for (final pill in state.crossStep)
            if (!superseded.contains(pill.item.id)) pill,
          for (final item in turn.crossStep)
            VoiceCrossPill(turnId: turn.turnId, item: item),
        ],
        turnIds: [..._appliedTurnIds],
      ),
    );
    if (_speakReplies) await _speak(turn.turnId);
    _inFlight = false;
    if (isClosed) return;
    if (_finishing) {
      await _completeFinish();
      return;
    }
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
    final update = item.updateOf;
    if (update != null) {
      final saved = await _pendingSink?.acceptPendingUpdate(update) ?? false;
      if (isClosed) return;
      if (!saved) {
        _fail(VoiceError.save);
        return;
      }
      _say(_localReplies.confirmed);
      if (state.phase != VoicePhase.listening) await _listen();
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
    // "Non" to the summary: the dictation goes on.
    if (item.isSummary) _finishing = false;
    final update = item.updateOf;
    if (update != null) {
      unawaited(_pendingSink?.rejectPending(update, cancelled: false));
    }
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
    // An entity operation (or a note) removed: the later ones of that
    // turn shift.
    for (final prefix in const ['op:', 'note:']) {
      if (!pill.key.startsWith(prefix)) continue;
      final index = int.parse(pill.key.substring(prefix.length));
      for (final (i, other) in remaining.indexed) {
        if (other.turnId != pill.turnId || !other.key.startsWith(prefix)) {
          continue;
        }
        final otherIndex = int.parse(other.key.substring(prefix.length));
        if (otherIndex > index) {
          remaining[i] = VoiceAppliedPill(
            turnId: other.turnId,
            key: '$prefix${otherIndex - 1}',
            label: other.label,
            changedLabel: other.changedLabel,
          );
        }
      }
    }
    emit(state.copyWith(applied: remaining));
  }

  /// The cross of a « Noté pour … » pill: that pending answer is dropped
  /// (and its update proposal with it).
  void undoCross(VoiceCrossPill pill) {
    if (isClosed || !state.crossStep.contains(pill)) return;
    unawaited(_pendingSink?.rejectPending(pill.item.id, cancelled: true));
    _reportUndone(pill.turnId);
    final update = '${VoicePendingConfirmation.updatePrefix}${pill.item.id}';
    emit(
      state.copyWith(
        crossStep: [
          for (final other in state.crossStep)
            if (other != pill) other,
        ],
        confirmations: [
          for (final other in state.confirmations)
            if (other.confirmation.id != update) other,
        ],
      ),
    );
  }

  void _reportUndone(String turnId) {
    // A confirmed change ("t1#c1") belongs to its agent turn.
    final id = turnId.split('#').first;
    if (!_undone.contains(id)) _undone.add(id);
  }

  /// "Terminer" / "terminé": the rooms dictation asks the spoken summary
  /// first ("9 pièces pour 115 m² habitables. Est-ce correct ?"); the
  /// other sheets end at once. A turn in flight is applied first; the
  /// microphone never listens again afterwards.
  Future<void> finish() async {
    if (_finishing) return;
    _finishing = true;
    if (_inFlight) return;
    await _completeFinish();
  }

  Future<void> _completeFinish() async {
    final summary = _summary;
    await _stopListening();
    if (isClosed) return;
    if (summary == null) {
      emit(state.copyWith(phase: VoicePhase.done, finished: true));
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
        // The summary is the only question left (shown once, in the
        // agent's bubble; the card only holds Oui / Non).
        confirmations: [
          VoicePendingConfirmation(
            turnId: turn.turnId,
            confirmation: const AgentConfirmation(
              id: VoicePendingConfirmation.summaryId,
              reason: AgentConfirmationReason.mediumConfidence,
              label: '',
            ),
          ),
        ],
      ),
    );
    await _speak(turn.turnId);
    // Waits for Oui / Non (tapped): nothing is listened to any more.
    if (!isClosed && state.phase == VoicePhase.speaking) {
      emit(state.copyWith(phase: VoicePhase.idle));
    }
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
    _inFlight = false;
    // EPIC-16: what keeps the sheet from opening by itself next time.
    final now = _clock();
    switch (error) {
      case VoiceError.quota:
        unawaited(_preferences.markQuotaReached(now));
      case VoiceError.network:
        unawaited(_preferences.markOffline(now));
      case VoiceError.permissionDenied:
        unawaited(_preferences.setMicDenied(denied: true));
      case VoiceError.empty ||
          VoiceError.locked ||
          VoiceError.tooLong ||
          VoiceError.save:
        break;
    }
    if (isClosed) return;
    // "Terminer" was asked meanwhile: the sheet ends anyway.
    if (_finishing) {
      unawaited(_completeFinish());
      return;
    }
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
