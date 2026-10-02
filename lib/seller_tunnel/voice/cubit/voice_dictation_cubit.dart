import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/voice/cubit/voice_conversation_cubit.dart';
import 'package:voice_repository/voice_repository.dart';

/// A plain dictation (EPIC-14, owner decision Q2): listen, then transcribe
/// only (`agent-transcribe` mode=dictation). The text never reaches the
/// language model nor the journal (the V2 address goes to the search
/// field, the seller picks the suggestion).
class VoiceDictationCubit extends Cubit<VoiceDictationState> {
  new({
    required this._agentRepository,
    required this._recorder,
    required this._propertyId,
    required this._step,
    DateTime Function()? clock,
    SpeechEndDetector? detector,
  }) : _clock = clock ?? DateTime.now,
       _detector = detector ?? SpeechEndDetector(),
       super(const VoiceDictationState());

  final AgentRepository _agentRepository;
  final VoiceRecorder _recorder;
  final String _propertyId;
  final AgentStep _step;
  final DateTime Function() _clock;
  final SpeechEndDetector _detector;

  StreamSubscription<double>? _levels;
  DateTime? _startedAt;

  /// Asks for the microphone, then listens.
  Future<void> start() async {
    if (!await _recorder.requestPermission()) {
      _fail(VoiceError.permissionDenied);
      return;
    }
    _detector.reset();
    emit(const VoiceDictationState(phase: VoicePhase.listening));
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
    if (_detector.add(db, elapsed)) unawaited(finish());
  }

  /// "J’ai fini" (or the detected end of speech): transcribes.
  Future<void> finish() async {
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
    try {
      final transcription = await _agentRepository.transcribe(
        propertyId: _propertyId,
        step: _step,
        audio: audio.bytes,
        duration: audio.duration,
        format: audio.format,
        dictation: true,
      );
      if (isClosed) return;
      final text = transcription.transcript.trim();
      emit(state.copyWith(phase: VoicePhase.done, text: () => text));
    } on Object catch (error) {
      _fail(switch (error) {
        AgentLockedFailure() => VoiceError.locked,
        AgentQuotaFailure() => VoiceError.quota,
        AgentEmptyFailure() => VoiceError.empty,
        AgentTooLongFailure() => VoiceError.tooLong,
        _ => VoiceError.network,
      });
    }
  }

  void _fail(VoiceError error) {
    if (isClosed) return;
    emit(state.copyWith(phase: VoicePhase.idle, error: () => error));
  }

  /// Stops listening (the sheet was closed).
  Future<void> cancel() async {
    await _levels?.cancel();
    _levels = null;
    await _recorder.cancel();
  }

  @override
  Future<void> close() async {
    await _levels?.cancel();
    await _recorder.dispose();
    await super.close();
  }
}

final class VoiceDictationState extends Equatable {
  const new({
    this.phase = VoicePhase.idle,
    this.levels = const [],
    this.text,
    this.error,
  });

  final VoicePhase phase;

  /// Last input levels (0…1).
  final List<double> levels;

  /// The transcription, once [VoicePhase.done].
  final String? text;
  final VoiceError? error;

  double get level => levels.isEmpty ? 0 : levels.last;

  VoiceDictationState copyWith({
    VoicePhase? phase,
    List<double>? levels,
    String? Function()? text,
    VoiceError? Function()? error,
  }) {
    return VoiceDictationState(
      phase: phase ?? this.phase,
      levels: levels ?? this.levels,
      text: text == null ? this.text : text(),
      error: error == null ? this.error : error(),
    );
  }

  @override
  List<Object?> get props => [phase, levels, text, error];
}
