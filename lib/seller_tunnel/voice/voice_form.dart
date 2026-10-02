import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:property_repository/property_repository.dart';

/// A step form the voice agent fills (EPIC-14, plan §5): it applies a
/// turn to its unsaved draft (nothing is saved before "Continuer") and
/// can undo it, a pill of it, or a whole sheet session.
abstract interface class VoiceForm {
  /// Applies what the agent understood (validated by the server).
  Future<void> voiceTurnApplied(AgentTurn turn);

  /// Undoes the turn [turnId] (and replays the later ones).
  void undoVoiceTurn(String turnId);

  /// Undoes the answer [key] of the turn [turnId] (a column, or `op:<i>`).
  void undoVoicePill(String turnId, String key);

  /// Number of turns applied so far (a sheet session starts there).
  int get voiceTurnCount;

  /// Undoes every turn from the [index]-th one (a whole sheet session).
  void undoVoiceTurnsFrom(int index);

  /// What the sheet sends with each turn: the draft of the step's columns,
  /// its rooms or estimates.
  AgentTurnContext get voiceContext;

  /// « Oui » said while no confirmation is waiting (EPIC-16): confirms the
  /// values pre-filled « À confirmer » on the step; false when there is
  /// none.
  bool confirmPrefilled();
}

/// Where the voice sheet sends what was said for other steps (EPIC-16):
/// the tunnel keeps the pending answers and resolves them.
abstract interface class VoicePendingSink {
  /// The pending answers recorded by a turn, and those they replaced.
  void pendingRecorded(List<AgentCrossStep> items, List<String> supersededIds);

  /// Whether [step] was already validated (before the resume point): its
  /// values are proposed as an update.
  bool isStepValidated(AgentStep step);

  /// « Oui » to the update of a validated step: saves it at once; false
  /// when the save failed.
  Future<bool> acceptPendingUpdate(String id);

  /// « Non » to an update, or the cross of a « Noté pour … » pill.
  Future<void> rejectPending(String id, {required bool cancelled});
}

/// [VoiceForm] for a step cubit: implement [applyVoiceTurn] (pure: the
/// draft after a turn) and [voiceContext]. Undoing restores the draft as
/// it was before the turn and applies the later turns again (the sheet is
/// modal: nothing is typed on the form meanwhile).
mixin VoiceFormMixin<S> on Cubit<S> implements VoiceForm {
  final List<(AgentTurn, S)> _voiceTurns = [];

  /// The draft [state] after [turn].
  S applyVoiceTurn(S state, AgentTurn turn);

  /// Whether a turn can change the draft now (not while saving).
  bool get acceptsVoice => true;

  @override
  bool confirmPrefilled() => false;

  /// The origin of [column] when it is saved with [value] (as stored): the
  /// last turn that gave it, when the value is still the one said (EPIC-16,
  /// `field_sources`); null when it was typed (or changed since).
  FieldSource? voiceSourceOf(String column, Object? value, DateTime at) {
    for (final (turn, _) in _voiceTurns.reversed) {
      if (!turn.patch.containsKey(column)) continue;
      if (!sameStoredValue(turn.patch[column], value)) return null;
      return FieldSource(
        kind: FieldSourceKind.dictated,
        at: at,
        // A confirmed change ("t1#c1") belongs to its agent turn.
        turnId: turn.turnId.split('#').first,
        evidenceKey: column,
      );
    }
    return null;
  }

  /// [turn] with its short references (R1, E2…, valid for the draft the
  /// agent saw: [state]) turned into stable ids, so that replaying it
  /// after an undo still aims at the same entities.
  AgentTurn resolveVoiceTurn(S state, AgentTurn turn) => turn;

  @override
  Future<void> voiceTurnApplied(AgentTurn turn) async {
    if (isClosed || !acceptsVoice) return;
    final before = state;
    final resolved = resolveVoiceTurn(before, turn);
    _voiceTurns.add((resolved, before));
    emit(applyVoiceTurn(before, resolved));
  }

  @override
  int get voiceTurnCount => _voiceTurns.length;

  @override
  void undoVoiceTurn(String turnId) => _replay(turnId, null);

  @override
  void undoVoicePill(String turnId, String key) => _replay(turnId, key);

  void _replay(String turnId, String? key) {
    final index = _voiceTurns.indexWhere((entry) => entry.$1.turnId == turnId);
    if (index < 0 || isClosed || !acceptsVoice) return;
    var next = _voiceTurns[index].$2;
    final undone = _voiceTurns[index].$1;
    final later = [for (final entry in _voiceTurns.skip(index + 1)) entry.$1];
    _voiceTurns.removeRange(index, _voiceTurns.length);
    for (final turn in [?key == null ? null : undone.without(key), ...later]) {
      _voiceTurns.add((turn, next));
      next = applyVoiceTurn(next, turn);
    }
    emit(next);
  }

  @override
  void undoVoiceTurnsFrom(int index) {
    if (index < 0 || index >= _voiceTurns.length || isClosed) return;
    if (!acceptsVoice) return;
    final before = _voiceTurns[index].$2;
    _voiceTurns.removeRange(index, _voiceTurns.length);
    emit(before);
  }
}

/// The agent step of a tunnel screen with a voice sheet.
AgentStep? agentStepOf(SellerTunnelStep step) => switch (step) {
  SellerTunnelStep.owners => null,
  SellerTunnelStep.location => AgentStep.location,
  SellerTunnelStep.context => AgentStep.context,
  SellerTunnelStep.technical => AgentStep.technical,
  SellerTunnelStep.method || SellerTunnelStep.surfaces => AgentStep.rooms,
  SellerTunnelStep.lifestyle => AgentStep.lifestyle,
  SellerTunnelStep.documents || SellerTunnelStep.submitted => null,
};

/// [values] encoded as the agent reads them: enums as their stored
/// value, lists item by item, empty texts as null.
Map<String, Object?> encodeVoiceDraft(Map<String, Object?> values) => {
  for (final MapEntry(:key, :value) in values.entries) key: _encode(value),
};

Object? _encode(Object? value) => switch (value) {
  final List<Object?> list => [for (final item in list) _encode(item)],
  final String text when text.trim().isEmpty => null,
  final DbEnum item => item.value,
  _ => value,
};

/// Whether two stored values are the same answer: lists as sets, numbers
/// to the cent, enums as their stored value.
bool sameStoredValue(Object? a, Object? b) {
  final left = _encode(a);
  final right = _encode(b);
  if (left is List && right is List) {
    return left.length == right.length && left.every(right.contains);
  }
  if (left is num && right is num) return (left - right).abs() < 0.005;
  return left == right;
}
