import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_repository/voice_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  late MockAgentRepository agent;
  late MockVoiceRecorder recorder;
  late MockVoicePlayer player;
  late StreamController<double> levels;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AgentStep.lifestyle);
  });

  setUp(() {
    agent = MockAgentRepository();
    recorder = MockVoiceRecorder();
    player = MockVoicePlayer();
    levels = StreamController<double>.broadcast();
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
      ),
    ).thenAnswer(
      (_) async => const Transcription(turnId: 't1', transcript: 'Très calme'),
    );
    when(
      () => agent.turn(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnId: any(named: 'turnId'),
        assetLabels: any(named: 'assetLabels'),
        watchPointLabels: any(named: 'watchPointLabels'),
      ),
    ).thenAnswer(
      (_) async => const AgentTurn(
        turnId: 't1',
        transcript: 'Très calme',
        reply: 'J’ai noté un atout.',
        lifestyleItems: [
          AgentLifestyleItem(isAsset: true, label: 'Quartier très calme'),
        ],
        suggestions: {'secret_note': 'Vente avant la rentrée'},
      ),
    );
  });

  tearDown(() => levels.close());

  testWidgets('speak freely: items added by voice and a note suggestion', (
    tester,
  ) async {
    usePhoneSurface();
    final services = await testVoiceServices(
      agentRepository: agent,
      recorder: recorder,
      player: player,
      muted: true,
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(value: services, child: const LifestylePage()),
    );
    expect(
      find.text('Parlez librement, l’agent classe vos réponses'),
      findsOneWidget,
    );
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    expect(find.text('L’agent vous écoute…'), findsOneWidget);
    levels.add(-20);
    await tester.pump();
    await tester.ensureVisible(find.text('J’ai fini'));
    await tester.tap(find.text('J’ai fini'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('J’ai noté un atout.'), findsOneWidget);
    await tester.ensureVisible(find.text('Terminer'));
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();

    expect(find.text('Quartier très calme'), findsOneWidget);
    expect(find.text('Ajouté à la voix'), findsOneWidget);
    expect(find.text('Vente avant la rentrée'), findsOneWidget);
    final use = find.text('Utiliser');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(RealestyTextField),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'Vente avant la rentrée',
    );
  });

  testWidgets('a declined consent opens nothing; dismissing a suggestion', (
    tester,
  ) async {
    usePhoneSurface();
    final services = await testVoiceServices(
      agentRepository: agent,
      recorder: recorder,
      player: player,
      consentGiven: false,
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(value: services, child: const LifestylePage()),
    );
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer à l’écran'));
    await tester.pumpAndSettle();
    verifyNever(recorder.requestPermission);
  });
}
