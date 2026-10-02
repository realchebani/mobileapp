import 'dart:typed_data';

import 'package:agent_repository/src/models.dart';
import 'package:supabase/supabase.dart';

/// Base class of the failures thrown by [AgentRepository].
sealed class AgentFailure implements Exception {
  const new([this.error]);

  final Object? error;

  String get _name;

  @override
  String toString() => '$_name($error)';
}

/// The dossier was sent: it can no longer be changed (HTTP 409).
final class AgentLockedFailure extends AgentFailure {
  const new([super.error]);

  @override
  String get _name => 'AgentLockedFailure';
}

/// The daily quota is reached (HTTP 429).
final class AgentQuotaFailure extends AgentFailure {
  const new([super.error]);

  @override
  String get _name => 'AgentQuotaFailure';
}

/// Nothing was heard in the recording (HTTP 422).
final class AgentEmptyFailure extends AgentFailure {
  const new([super.error]);

  @override
  String get _name => 'AgentEmptyFailure';
}

/// The recording is too long (HTTP 413).
final class AgentTooLongFailure extends AgentFailure {
  const new([super.error]);

  @override
  String get _name => 'AgentTooLongFailure';
}

/// Any other failure (network, AI provider…). [turnId] is set when the
/// turn was recorded before the failure (retry with it).
final class AgentRequestFailure extends AgentFailure {
  const new([super.error, this.turnId]);

  final String? turnId;

  @override
  String get _name => 'AgentRequestFailure';
}

/// Calls the voice agent Edge Functions with the signed-in user's session
/// (RLS). The OpenRouter key never reaches the app.
class AgentRepository {
  new({required this._functions, this._timeout = const Duration(seconds: 45)});

  final FunctionsClient _functions;
  final Duration _timeout;

  /// Transcribes a recorded utterance (`m4a` by default) for [propertyId].
  ///
  /// [dictation] (V2 address): transcription only, never sent to the
  /// language model nor kept in the journal; the transcript is not an
  /// agent turn.
  Future<Transcription> transcribe({
    required String propertyId,
    required AgentStep step,
    required Uint8List audio,
    required Duration duration,
    String format = 'm4a',
    bool dictation = false,
  }) async {
    final data = await _invoke(
      'agent-transcribe',
      body: audio,
      query: {
        'property_id': propertyId,
        'step': step.value,
        'format': format,
        'duration': (duration.inMilliseconds / 1000).toStringAsFixed(2),
        if (dictation) 'mode': 'dictation',
      },
    );
    final json = Map<String, dynamic>.from(data! as Map);
    return Transcription(
      turnId: json['turn_id'] as String,
      transcript: json['transcript'] as String,
    );
  }

  /// One agent turn: on a transcribed [turnId], or on a typed
  /// [transcript]. [assetLabels] / [watchPointLabels] are the V6 items
  /// listed on screen (not saved yet), to avoid duplicates. [context] is
  /// what a step sheet sends (draft, rooms, estimates; EPIC-14);
  /// [undoneTurnIds] are the turns the seller undid since the last call.
  Future<AgentTurn> turn({
    required String propertyId,
    required AgentStep step,
    String? turnId,
    String? transcript,
    List<String> assetLabels = const [],
    List<String> watchPointLabels = const [],
    AgentTurnContext? context,
    List<String> undoneTurnIds = const [],
  }) async {
    final data = await _invoke(
      'agent-turn',
      body: {
        'property_id': propertyId,
        'step': step.value,
        'turn_id': ?turnId,
        'transcript': ?transcript,
        if (step == AgentStep.lifestyle)
          'lifestyle_labels': {
            'asset': assetLabels,
            'watch_point': watchPointLabels,
          },
        ...?context?.toJson(),
        if (undoneTurnIds.isNotEmpty) 'undone_turn_ids': undoneTurnIds,
      },
    );
    return AgentTurn.fromJson(Map<String, dynamic>.from(data! as Map));
  }

  /// The spoken summary of a rooms dictation ("J’ai noté 9 pièces pour
  /// 115 m² habitables. Est-ce correct ?"), computed by the server from
  /// [rooms] without the language model; speak it with [speech].
  Future<AgentTurn> roomsSummary({
    required String propertyId,
    required List<AgentRoom> rooms,
  }) async {
    final data = await _invoke(
      'agent-turn',
      body: {
        'property_id': propertyId,
        'step': AgentStep.rooms.value,
        'summary': true,
        'rooms': [for (final room in rooms) room.toJson()],
      },
    );
    return AgentTurn.fromJson(Map<String, dynamic>.from(data! as Map));
  }

  /// Reports the turns the seller undid (quality follow-up, plan §7.4).
  Future<void> markUndone({
    required String propertyId,
    required AgentStep step,
    required List<String> turnIds,
  }) async {
    if (turnIds.isEmpty) return;
    await _invoke(
      'agent-turn',
      body: {
        'property_id': propertyId,
        'step': step.value,
        'undone_turn_ids': turnIds,
      },
    );
  }

  /// The spoken reply of [turnId] (each reply is spoken once).
  Future<AgentSpeech> speech(String turnId) async {
    final data = await _invoke('agent-speech', body: {'turn_id': turnId});
    if (data is! Uint8List) throw const AgentRequestFailure('no audio');
    return AgentSpeech(bytes: data, format: _speechFormat(data));
  }

  /// `wav` when the bytes start with a RIFF header, `mp3` otherwise.
  static String _speechFormat(Uint8List bytes) =>
      bytes.length >= 4 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46
      ? 'wav'
      : 'mp3';

  Future<Object?> _invoke(
    String function, {
    required Object body,
    Map<String, String>? query,
  }) async {
    try {
      final response = await _functions
          .invoke(function, body: body, queryParameters: query)
          .timeout(_timeout);
      return response.data;
    } on Object catch (error) {
      _failure(error);
    }
  }

  static Never _failure(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      final turnId = details is Map ? details['turn_id'] as String? : null;
      throw switch ((error.status, code)) {
        (409, 'locked') => AgentLockedFailure(error),
        (429, _) => AgentQuotaFailure(error),
        (422, _) => AgentEmptyFailure(error),
        (413, _) => AgentTooLongFailure(error),
        _ => AgentRequestFailure(error, turnId),
      };
    }
    throw AgentRequestFailure(error);
  }
}
