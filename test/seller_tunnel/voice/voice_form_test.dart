import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:property_repository/property_repository.dart';

/// A form whose draft is the list of the patch keys applied.
class VoiceFormTest extends Cubit<List<String>>
    with VoiceFormMixin<List<String>> {
  new() : super(const []);

  bool _open = true;

  /// Blocks the voice turns (as while saving).
  void block() => _open = false;

  /// Accepts the voice turns again.
  void unblock() => _open = true;

  @override
  bool get acceptsVoice => _open;

  @override
  AgentTurnContext get voiceContext => const AgentTurnContext();

  @override
  List<String> applyVoiceTurn(List<String> state, AgentTurn turn) => [
    ...state,
    ...turn.patch.keys,
    for (final op in turn.entityOps) op.label,
  ];
}

AgentTurn _turn(
  String id,
  List<String> columns, [
  List<String> ops = const [],
]) => AgentTurn(
  turnId: id,
  transcript: '',
  reply: '',
  patch: {for (final column in columns) column: 1},
  entityOps: [
    for (final label in ops)
      AgentEntityChange(
        entity: AgentEntity.room,
        op: AgentEntityOp.create,
        target: 'new',
        label: label,
      ),
  ],
);

void main() {
  group(VoiceFormMixin, () {
    test('applies turns and undoes a turn, a pill or a session', () async {
      final form = VoiceFormTest();
      await form.voiceTurnApplied(_turn('t1', ['a', 'b']));
      await form.voiceTurnApplied(_turn('t2', ['c'], ['R']));
      expect(form.state, ['a', 'b', 'c', 'R']);
      expect(form.voiceTurnCount, 2);

      form.undoVoicePill('t1', 'a');
      expect(form.state, ['b', 'c', 'R']);
      form.undoVoicePill('t2', 'op:0');
      expect(form.state, ['b', 'c']);
      form.undoVoiceTurn('t1');
      expect(form.state, ['c']);
      expect(form.voiceTurnCount, 1);
      form.undoVoiceTurn('nope');
      expect(form.state, ['c']);

      await form.voiceTurnApplied(_turn('t3', ['d']));
      form.undoVoiceTurnsFrom(0);
      expect(form.state, isEmpty);
      expect(form.voiceTurnCount, 0);
      form
        ..undoVoiceTurnsFrom(0)
        ..undoVoiceTurnsFrom(-1);
      expect(form.state, isEmpty);
    });

    test('nothing changes while the form is busy or closed', () async {
      final form = VoiceFormTest();
      await form.voiceTurnApplied(_turn('t1', ['a']));
      form.block();
      await form.voiceTurnApplied(_turn('t2', ['b']));
      form
        ..undoVoiceTurn('t1')
        ..undoVoiceTurnsFrom(0);
      expect(form.state, ['a']);
      form.unblock();
      await form.close();
      await form.voiceTurnApplied(_turn('t3', ['c']));
      form
        ..undoVoiceTurn('t1')
        ..undoVoiceTurnsFrom(0);
      expect(form.state, ['a']);
    });
  });

  test('agentStepOf', () {
    expect(agentStepOf(SellerTunnelStep.owners), AgentStep.owners);
    expect(agentStepOf(SellerTunnelStep.location), AgentStep.location);
    expect(agentStepOf(SellerTunnelStep.context), AgentStep.context);
    expect(agentStepOf(SellerTunnelStep.technical), AgentStep.technical);
    expect(agentStepOf(SellerTunnelStep.method), AgentStep.rooms);
    expect(agentStepOf(SellerTunnelStep.surfaces), AgentStep.rooms);
    expect(agentStepOf(SellerTunnelStep.lifestyle), AgentStep.lifestyle);
    expect(agentStepOf(SellerTunnelStep.documents), isNull);
    expect(agentStepOf(SellerTunnelStep.submitted), isNull);
  });

  test('encodeVoiceDraft', () {
    expect(
      encodeVoiceDraft({
        'a': PropertyType.house,
        'b': [HeatingSystem.gas, 'x'],
        'c': '  ',
        'd': 3,
        'e': 'texte',
      }),
      {
        'a': 'maison',
        'b': ['gaz', 'x'],
        'c': null,
        'd': 3,
        'e': 'texte',
      },
    );
  });
}
