import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_repository/voice_repository.dart';

import 'mocks.dart';
import 'voice.dart';

/// Mocks of a step voice sheet (EPIC-14): a recorder that hears speech,
/// a transcription, and the given turn as the agent’s answer. Call
/// `dispose` in a tear-down.
class VoiceSheetMocks {
  new({AgentTurn? turn, String transcript = 'réponse'})
    : agent = MockAgentRepository(),
      recorder = MockVoiceRecorder(),
      player = MockVoicePlayer(),
      levels = StreamController<double>.broadcast() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AgentStep.location);
    registerFallbackValue(const AgentTurnContext());
    when(recorder.requestPermission).thenAnswer((_) async => true);
    when(recorder.start).thenAnswer((_) async {});
    when(recorder.levels).thenAnswer((_) => levels.stream);
    when(recorder.cancel).thenAnswer((_) async {});
    when(recorder.dispose).thenAnswer((_) async {});
    when(recorder.stop).thenAnswer(
      (_) async => RecordedAudio(
        bytes: Uint8List.fromList([1]),
        duration: const Duration(seconds: 3),
      ),
    );
    when(player.stop).thenAnswer((_) async {});
    when(player.dispose).thenAnswer((_) async {});
    when(
      () => agent.transcribe(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        audio: any(named: 'audio'),
        duration: any(named: 'duration'),
        format: any(named: 'format'),
        dictation: any(named: 'dictation'),
      ),
    ).thenAnswer(
      (_) async => Transcription(turnId: 't1', transcript: transcript),
    );
    if (turn != null) answer(turn);
    when(
      () => agent.markUndone(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnIds: any(named: 'turnIds'),
      ),
    ).thenAnswer((_) async {});
  }

  final MockAgentRepository agent;
  final MockVoiceRecorder recorder;
  final MockVoicePlayer player;
  final StreamController<double> levels;

  /// The agent answers [turn].
  void answer(AgentTurn turn) => when(
    () => agent.turn(
      propertyId: any(named: 'propertyId'),
      step: any(named: 'step'),
      turnId: any(named: 'turnId'),
      assetLabels: any(named: 'assetLabels'),
      watchPointLabels: any(named: 'watchPointLabels'),
      context: any(named: 'context'),
      undoneTurnIds: any(named: 'undoneTurnIds'),
    ),
  ).thenAnswer((_) async => turn);

  /// Voice services on these mocks (agent muted: nothing spoken).
  Future<VoiceServices> services({
    bool consentGiven = true,
    VoiceInputMode inputMode = VoiceInputMode.text,
  }) => testVoiceServices(
    agentRepository: agent,
    recorder: recorder,
    player: player,
    muted: true,
    consentGiven: consentGiven,
    inputMode: inputMode,
  );

  /// The context sent with the last agent turn.
  AgentTurnContext? lastContext() =>
      verify(
            () => agent.turn(
              propertyId: any(named: 'propertyId'),
              step: any(named: 'step'),
              turnId: any(named: 'turnId'),
              assetLabels: any(named: 'assetLabels'),
              watchPointLabels: any(named: 'watchPointLabels'),
              context: captureAny(named: 'context'),
              undoneTurnIds: any(named: 'undoneTurnIds'),
            ),
          ).captured.last
          as AgentTurnContext?;

  /// The seller speaks, then taps "J’ai fini": the turn is applied.
  Future<void> speak(WidgetTester tester) async {
    levels.add(-20);
    await tester.pump();
    await tester.ensureVisible(find.text('J’ai fini'));
    await tester.tap(find.text('J’ai fini'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// "Terminer": closes the sheet.
  Future<void> close(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Terminer'));
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() => levels.close();
}
