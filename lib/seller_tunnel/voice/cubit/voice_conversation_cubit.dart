import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:voice_repository/voice_repository.dart';

part 'voice_conversation_state.dart';

/// Applies an agent turn to the step (writes through the tunnel cubit or
/// the step's form). Throwing stops the loop with [VoiceError.save].
typedef VoiceTurnHandler = Future<void> Function(AgentTurn turn);

/// The voice loop of V4 and V6: listen → transcribe (`agent-transcribe`)
/// → agent turn (`agent-turn`) → apply ([VoiceTurnHandler]) → speak
/// (`agent-speech`, unless muted) → listen again. The microphone is off
/// while the agent speaks; a speech failure never blocks the
/// conversation (text only).
class VoiceConversationCubit extends Cubit<VoiceConversationState> {
  new({
    required this._agentRepository,
    required this._recorder,
    required this._player,
    required this._preferences,
    required this._propertyId,
    required this._step,
    required String intro,
    required this._onTurn,
    List<String> Function()? assetLabels,
    List<String> Function()? watchPointLabels,
    DateTime Function()? clock,
    SpeechEndDetector? detector,
  }) : _assetLabels = assetLabels ?? _none,
       _watchPointLabels = watchPointLabels ?? _none,
       _clock = clock ?? DateTime.now,
       _detector = detector ?? SpeechEndDetector(),
       super(
         VoiceConversationState(
           messages: [VoiceMessage(text: intro, fromAgent: true)],
           muted: _preferences.agentMuted,
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
    await _turn(transcription.turnId);
  }

  Future<void> _turn(String turnId) async {
    final AgentTurn turn;
    try {
      turn = await _agentRepository.turn(
        propertyId: _propertyId,
        step: _step,
        turnId: turnId,
        assetLabels: _assetLabels(),
        watchPointLabels: _watchPointLabels(),
      );
    } on Object catch (error) {
      _retryTurnId = switch (error) {
        AgentRequestFailure() => turnId,
        _ => null,
      };
      _failWith(error);
      return;
    }
    _retryTurnId = null;
    // The screen was left meanwhile: nothing is applied any more.
    if (isClosed || _stopped) return;
    await _apply(turn);
  }

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
    final understood =
        turn.patch.isNotEmpty ||
        turn.lifestyleItems.isNotEmpty ||
        turn.suggestions.isNotEmpty;
    _misses = understood ? 0 : _misses + 1;
    final facts = {
      for (final fact in state.facts) fact.field: fact,
      for (final fact in turn.facts) fact.field: fact,
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
      ),
    );
    await _speak(turn.turnId);
    if (isClosed) return;
    if (turn.done) {
      emit(state.copyWith(phase: VoicePhase.done));
      return;
    }
    await _listen();
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

  /// Stops listening and speaking (leaving the screen).
  Future<void> stop() async {
    _paused = true;
    _stopped = true;
    await _levels?.cancel();
    _levels = null;
    await _recorder.cancel();
    await _player.stop();
  }

  @override
  Future<void> close() async {
    await _levels?.cancel();
    await _recorder.dispose();
    await _player.dispose();
    await super.close();
  }
}
