import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_form.dart';
import 'package:property_repository/property_repository.dart';

part 'step_trace_state.dart';

/// The « Notes complémentaires » of a step and its pending answers
/// pre-filled « À confirmer » (EPIC-16), next to the step's own cubit.
/// The notes said in a voice turn are appended; undoing a turn restores
/// them.
class StepTraceCubit extends Cubit<StepTraceState> {
  new(super.initialState);

  /// Turns applied, each with the notes as they were before it.
  final List<(AgentTurn, StepTraceState)> _turns = [];

  /// The turns applied so far, oldest first.
  List<AgentTurn> _applied() => [for (final (turn, _) in _turns) turn];

  /// The seller typed the notes.
  void notesChanged(String value) =>
      emit(state.copyWith(notes: StepTraceState._cut(value)));

  /// Appends the notes said in [turn] (nothing else changes here).
  void turnApplied(AgentTurn turn) {
    if (isClosed) return;
    _turns.add((turn, state));
    emit(_withNotes(state, turn));
  }

  StepTraceState _withNotes(StepTraceState state, AgentTurn turn) {
    if (state.noteKey == null || turn.notes.isEmpty) return state;
    final notes = StepTraceState._cut(
      [
        if (state.notes.trim().isNotEmpty) state.notes.trim(),
        ...turn.notes,
      ].join(StepTraceState.separator),
    );
    return state.copyWith(
      notes: notes,
      dictatedNotes: () => notes,
      notesTurnId: () => turn.turnId.split('#').first,
    );
  }

  /// Restores the notes as before [turnId], then applies [replay] again
  /// (the later turns, or that turn without one of its notes).
  void undoFrom(String turnId, {List<AgentTurn> replay = const []}) {
    final index = _turns.indexWhere((t) => t.$1.turnId == turnId);
    if (index < 0 || isClosed) return;
    final before = _turns[index].$2;
    _turns.removeRange(index, _turns.length);
    // Typed changes and confirmations made since are kept.
    var next = state.copyWith(
      notes: before.notes,
      dictatedNotes: () => before.dictatedNotes,
      notesTurnId: () => before.notesTurnId,
    );
    for (final turn in replay) {
      _turns.add((turn, next));
      next = _withNotes(next, turn);
    }
    emit(next);
  }

  /// « Oui » with nothing else to confirm: every pre-filled answer still
  /// shown is confirmed (« Dicté ✓ »).
  void confirmPrefilled() => _confirmAll();

  /// [confirmPrefilled]; false when there was nothing to confirm.
  bool _confirmAll() {
    final open = [
      for (final answer in state.prefilled)
        if (!state.confirmed.contains(answer.id)) answer.id,
    ];
    if (open.isEmpty || isClosed) return false;
    emit(state.copyWith(confirmed: {...state.confirmed, ...open}));
    return true;
  }
}

/// The [VoiceForm] of a step sheet with notes and pre-filled answers: the
/// step's [form] gets the turns (its answers), [trace] their notes.
class TracedVoiceForm implements VoiceForm {
  const new({required this.form, required this.trace});

  final VoiceForm form;
  final StepTraceCubit trace;

  @override
  Future<void> voiceTurnApplied(AgentTurn turn) async {
    final before = form.voiceTurnCount;
    await form.voiceTurnApplied(turn);
    // Ignored by the form (saving): ignored here too.
    if (form.voiceTurnCount != before) trace.turnApplied(turn);
  }

  @override
  void undoVoiceTurn(String turnId) {
    form.undoVoiceTurn(turnId);
    final turns = trace._applied();
    final index = turns.indexWhere((t) => t.turnId == turnId);
    if (index < 0) return;
    trace.undoFrom(turnId, replay: turns.sublist(index + 1));
  }

  @override
  void undoVoicePill(String turnId, String key) {
    if (!key.startsWith('note:')) {
      form.undoVoicePill(turnId, key);
      return;
    }
    final turns = trace._applied();
    final index = turns.indexWhere((t) => t.turnId == turnId);
    if (index < 0) return;
    trace.undoFrom(
      turnId,
      replay: [turns[index].without(key), ...turns.skip(index + 1)],
    );
  }

  @override
  int get voiceTurnCount => form.voiceTurnCount;

  @override
  void undoVoiceTurnsFrom(int index) {
    final turns = trace._applied();
    form.undoVoiceTurnsFrom(index);
    if (index >= 0 && index < turns.length) {
      trace.undoFrom(turns[index].turnId);
    }
  }

  @override
  AgentTurnContext get voiceContext => form.voiceContext;

  @override
  bool confirmPrefilled() => trace._confirmAll() || form.confirmPrefilled();
}
