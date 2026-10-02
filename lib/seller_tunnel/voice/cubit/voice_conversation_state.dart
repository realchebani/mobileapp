part of 'voice_conversation_cubit.dart';

/// Where the conversation loop is.
enum VoicePhase {
  /// Not started, or stopped by an error ([VoiceConversationState.error]).
  idle,

  /// Recording the seller (until a silence or "J’ai fini").
  listening,

  /// Sending the recording to the transcription.
  transcribing,

  /// Waiting for the agent's answer.
  thinking,

  /// Playing the agent's reply (microphone off).
  speaking,

  /// Paused by the seller.
  paused,

  /// The agent has everything it needs.
  done,
}

/// Why the loop stopped.
enum VoiceError {
  /// The microphone access is refused.
  permissionDenied,

  /// Nothing was heard.
  empty,

  /// Network or AI provider failure (retry).
  network,

  /// The daily quota is reached.
  quota,

  /// The dossier was sent.
  locked,

  /// The utterance is too long.
  tooLong,

  /// The answers could not be saved (retry).
  save,
}

/// A line of the conversation.
final class VoiceMessage extends Equatable {
  const new({required this.text, required this.fromAgent});

  final String text;
  final bool fromAgent;

  @override
  List<Object?> get props => [text, fromAgent];
}

final class VoiceConversationState extends Equatable {
  const new({
    this.phase = VoicePhase.idle,
    this.messages = const [],
    this.facts = const [],
    this.pending = const [],
    this.levels = const [],
    this.error,
    this.muted = false,
  });

  /// Bars of the waveform.
  static const levelCount = 34;

  final VoicePhase phase;
  final List<VoiceMessage> messages;

  /// Understood answers of the session (latest per field).
  final List<AgentPill> facts;

  /// Answers to clarify ("Assainissement ?").
  final List<AgentPill> pending;

  /// Last input levels (0…1), oldest first, at most [levelCount].
  final List<double> levels;
  final VoiceError? error;

  /// Whether the agent's voice is muted (text only).
  final bool muted;

  /// The current input level (0…1).
  double get level => levels.isEmpty ? 0 : levels.last;

  VoiceConversationState copyWith({
    VoicePhase? phase,
    List<VoiceMessage>? messages,
    List<AgentPill>? facts,
    List<AgentPill>? pending,
    List<double>? levels,
    VoiceError? Function()? error,
    bool? muted,
  }) {
    return VoiceConversationState(
      phase: phase ?? this.phase,
      messages: messages ?? this.messages,
      facts: facts ?? this.facts,
      pending: pending ?? this.pending,
      levels: levels ?? this.levels,
      error: error == null ? this.error : error(),
      muted: muted ?? this.muted,
    );
  }

  @override
  List<Object?> get props => [
    phase,
    messages,
    facts,
    pending,
    levels,
    error,
    muted,
  ];
}
