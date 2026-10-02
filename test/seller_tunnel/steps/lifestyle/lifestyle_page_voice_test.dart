import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
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
    registerFallbackValue(const AgentTurnContext());
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
        context: any(named: 'context'),
        undoneTurnIds: any(named: 'undoneTurnIds'),
      ),
    ).thenAnswer(
      (_) async => const AgentTurn(
        turnId: 't1',
        transcript: 'Très calme',
        reply: 'J’ai noté un atout.',
        patch: {'noise_level': 2},
        facts: [AgentPill(field: 'noise_level', label: 'Bruit 2/10')],
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
    // EPIC-14: the noise said is tagged "Dicté"; the snackbar offers to
    // undo the session.
    expect(find.text('Dicté'), findsOneWidget);
    expect(find.text('1 réponse ajoutée'), findsOneWidget);
    verify(
      () => agent.turn(
        propertyId: 'property-id',
        step: AgentStep.lifestyle,
        turnId: 't1',
        assetLabels: [],
        watchPointLabels: [],
        context: const AgentTurnContext(
          draft: {'noise_level': null, 'overlooking': null},
        ),
        undoneTurnIds: [],
      ),
    ).called(1);
    expect(find.text('Vente avant la rentrée'), findsOneWidget);
    final use = find.text('Utiliser');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(RealestyTextField).first,
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

  testWidgets('the session can be undone from the snackbar', (tester) async {
    usePhoneSurface();
    when(
      () => agent.markUndone(
        propertyId: any(named: 'propertyId'),
        step: any(named: 'step'),
        turnIds: any(named: 'turnIds'),
      ),
    ).thenAnswer((_) async {});
    final services = await testVoiceServices(
      agentRepository: agent,
      recorder: recorder,
      player: player,
      muted: true,
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(value: services, child: const LifestylePage()),
    );
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    levels.add(-20);
    await tester.pump();
    await tester.tap(find.text('J’ai fini'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Terminer'));
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    expect(find.text('Quartier très calme'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Quartier très calme'), findsNothing);
    verify(
      () => agent.markUndone(
        propertyId: 'property-id',
        step: AgentStep.lifestyle,
        turnIds: ['t1'],
      ),
    ).called(1);
  });

  testWidgets('voice for land too (EPIC-14)', (tester) async {
    usePhoneSurface();
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await testVoiceServices(),
        child: const LifestylePage(),
      ),
      sellerTunnelCubit: mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'p',
            ownerId: 'u',
            propertyType: PropertyType.land,
          ),
        ),
      ),
    );
    expect(find.byType(RealestyMicButton), findsOneWidget);
    expect(
      find.text('Parlez librement, l’agent classe vos réponses'),
      findsOneWidget,
    );
  });
}
