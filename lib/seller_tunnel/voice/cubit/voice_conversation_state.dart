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

  /// The agent has everything it needs (or the seller said "terminé").
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

/// An answer applied to the step's form during this sheet session, with
/// its "Annuler" cross (EPIC-14).
final class VoiceAppliedPill extends Equatable {
  const new({
    required this.turnId,
    required this.key,
    required this.label,
    this.changedLabel,
  });

  final String turnId;

  /// A column, or `op:<index>` of the turn's entity operations.
  final String key;
  final String label;

  /// "Modifié : 1998 → 1999".
  final String? changedLabel;

  @override
  List<Object?> get props => [turnId, key, label, changedLabel];
}

/// A value said for another step during this sheet session (EPIC-16):
/// « Noté pour Technique · Construction 1998 ».
final class VoiceCrossPill extends Equatable {
  const new({required this.turnId, required this.item});

  final String turnId;
  final AgentCrossStep item;

  @override
  List<Object?> get props => [turnId, item];
}

/// A change waiting for the seller's "Oui" (a pill with Oui / Non).
final class VoicePendingConfirmation extends Equatable {
  const new({required this.turnId, required this.confirmation});

  final String turnId;
  final AgentConfirmation confirmation;

  /// The end of a rooms dictation: "Est-ce correct ?" (no change).
  bool get isSummary => confirmation.id == summaryId;

  static const summaryId = 'summary';

  /// Prefix of the id of an update of a validated step (EPIC-16):
  /// `update:<pending answer id>`.
  static const updatePrefix = 'update:';

  /// The pending answer this confirmation updates, or null.
  String? get updateOf => confirmation.id.startsWith(updatePrefix)
      ? confirmation.id.substring(updatePrefix.length)
      : null;

  @override
  List<Object?> get props => [turnId, confirmation];
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
    this.suggestScreenMode = false,
    this.applied = const [],
    this.confirmations = const [],
    this.outOfStep = const [],
    this.crossStep = const [],
    this.turnIds = const [],
    this.sessionStart = 0,
    this.finished = false,
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

  /// Nothing was understood for several turns: the screen mode is offered.
  final bool suggestScreenMode;

  /// What this sheet session applied to the form, oldest first.
  final List<VoiceAppliedPill> applied;

  /// Changes waiting for "Oui" / "Non".
  final List<VoicePendingConfirmation> confirmations;

  /// Answers about other steps ("Construction → Technique").
  final List<AgentOutOfStep> outOfStep;

  /// Values said for other steps, kept as pending answers (EPIC-16).
  final List<VoiceCrossPill> crossStep;

  /// Turns applied to the form in this sheet session, oldest first (the
  /// last one can be undone).
  final List<String> turnIds;

  /// Number of form turns when this session started (to undo it all).
  final int sessionStart;

  /// Number of turns applied in this session.
  int get appliedTurns => turnIds.length;

  /// The seller ended the sheet ("terminé", or "oui" to the summary).
  final bool finished;

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
    bool? suggestScreenMode,
    List<VoiceAppliedPill>? applied,
    List<VoicePendingConfirmation>? confirmations,
    List<AgentOutOfStep>? outOfStep,
    List<VoiceCrossPill>? crossStep,
    List<String>? turnIds,
    bool? finished,
  }) {
    return VoiceConversationState(
      phase: phase ?? this.phase,
      messages: messages ?? this.messages,
      facts: facts ?? this.facts,
      pending: pending ?? this.pending,
      levels: levels ?? this.levels,
      error: error == null ? this.error : error(),
      muted: muted ?? this.muted,
      suggestScreenMode: suggestScreenMode ?? this.suggestScreenMode,
      applied: applied ?? this.applied,
      confirmations: confirmations ?? this.confirmations,
      outOfStep: outOfStep ?? this.outOfStep,
      crossStep: crossStep ?? this.crossStep,
      turnIds: turnIds ?? this.turnIds,
      sessionStart: sessionStart,
      finished: finished ?? this.finished,
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
    suggestScreenMode,
    applied,
    confirmations,
    outOfStep,
    crossStep,
    turnIds,
    sessionStart,
    finished,
  ];
}
