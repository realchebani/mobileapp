import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Tunnel step the agent works on (`agent_sessions.step`).
enum AgentStep {
  /// V4 · audit technique (fields of V4b).
  technical('technical'),

  /// V6 · cadre de vie.
  lifestyle('lifestyle');

  new(this.value);

  final String value;
}

/// A recorded utterance, transcribed (`agent-transcribe`).
final class Transcription extends Equatable {
  const new({required this.turnId, required this.transcript});

  final String turnId;
  final String transcript;

  @override
  List<Object?> get props => [turnId, transcript];
}

/// A pill of the conversation: an understood answer ("Construction 1998")
/// or a pending question ("Assainissement ?").
final class AgentPill extends Equatable {
  const new({required this.field, required this.label});

  new fromJson(Map<String, dynamic> json)
    : this(field: json['field'] as String, label: json['label_fr'] as String);

  /// The `properties` column.
  final String field;

  /// French label (from the server).
  final String label;

  @override
  List<Object?> get props => [field, label];
}

/// A lifestyle item proposed by the agent (V6).
final class AgentLifestyleItem extends Equatable {
  const new({required this.isAsset, required this.label});

  new fromJson(Map<String, dynamic> json)
    : this(isAsset: json['kind'] == 'asset', label: json['label'] as String);

  /// An asset, otherwise a watch point.
  final bool isAsset;
  final String label;

  @override
  List<Object?> get props => [isAsset, label];
}

/// The answer of one agent turn (`agent-turn`). The server validated
/// [patch]: column → value as stored (codes, numbers, lists). The app
/// writes it itself.
final class AgentTurn extends Equatable {
  const new({
    required this.turnId,
    required this.transcript,
    required this.reply,
    this.patch = const {},
    this.facts = const [],
    this.pending = const [],
    this.lifestyleItems = const [],
    this.suggestions = const {},
    this.nextField,
    this.done = false,
  });

  new fromJson(Map<String, dynamic> json)
    : this(
        turnId: json['turn_id'] as String,
        transcript: json['transcript'] as String? ?? '',
        reply: json['reply_fr'] as String? ?? '',
        patch: Map<String, Object?>.from(
          json['patch'] as Map? ?? const <String, Object?>{},
        ),
        facts: [
          for (final pill in json['facts'] as List? ?? const [])
            AgentPill.fromJson(Map<String, dynamic>.from(pill as Map)),
        ],
        pending: [
          for (final pill in json['pending'] as List? ?? const [])
            AgentPill.fromJson(Map<String, dynamic>.from(pill as Map)),
        ],
        lifestyleItems: [
          for (final item in json['lifestyle_items'] as List? ?? const [])
            AgentLifestyleItem.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        suggestions: Map<String, String>.from(
          json['suggestions'] as Map? ?? const <String, String>{},
        ),
        nextField: json['next_field'] as String?,
        done: json['done'] as bool? ?? false,
      );

  final String turnId;
  final String transcript;

  /// The agent's reply, in French.
  final String reply;
  final Map<String, Object?> patch;
  final List<AgentPill> facts;
  final List<AgentPill> pending;
  final List<AgentLifestyleItem> lifestyleItems;

  /// Proposed, never imposed (e.g. `secret_note`).
  final Map<String, String> suggestions;
  final String? nextField;

  /// Whether nothing useful is missing any more.
  final bool done;

  @override
  List<Object?> get props => [
    turnId,
    transcript,
    reply,
    patch,
    facts,
    pending,
    lifestyleItems,
    suggestions,
    nextField,
    done,
  ];
}

/// Spoken reply (`agent-speech`).
final class AgentSpeech extends Equatable {
  const new({required this.bytes, required this.format});

  final Uint8List bytes;

  /// `mp3` or `wav`.
  final String format;

  @override
  List<Object?> get props => [bytes, format];
}
