import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:voice_repository/voice_repository.dart';

import '../../../helpers/helpers.dart';

class _MockGoRouterState extends Mock implements GoRouterState;

const _living = Room(
  id: 'r1',
  propertyId: 'property-id',
  name: 'Séjour',
  level: RoomLevel.groundFloor,
  areaM2: 38,
  isMain: true,
  description: 'Ouvert sur la cuisine',
);

const _office = AgentTurn(
  turnId: 't1',
  transcript: 'un bureau de 9 m², parquet',
  reply: 'Bureau noté.',
  entityOps: [
    AgentEntityChange(
      entity: AgentEntity.room,
      op: AgentEntityOp.create,
      target: 'new',
      label: 'Bureau · 9 m²',
      values: {
        'name': 'Bureau',
        'kind': 'office',
        'area_m2': 9,
        'floor_covering': 'parquet',
        'description': 'Fenêtre sur le jardin',
      },
    ),
  ],
);

void main() {
  late MockAgentRepository agent;
  late MockVoiceRecorder recorder;
  late MockVoicePlayer player;
  late StreamController<double> levels;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AgentStep.rooms);
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
      (_) async => const Transcription(
        turnId: 't1',
        transcript: 'un bureau de 9 m², parquet',
      ),
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
    ).thenAnswer((_) async => _office);
    when(
      () => agent.roomsSummary(
        propertyId: any(named: 'propertyId'),
        rooms: any(named: 'rooms'),
      ),
    ).thenAnswer(
      (_) async => const AgentTurn(
        turnId: 'ts',
        transcript: '',
        reply: 'J’ai noté 2 pièces pour 47 m² habitables. Est-ce correct ?',
      ),
    );
  });

  tearDown(() => levels.close());

  Future<void> pump(WidgetTester tester, {GoRouter? goRouter}) async {
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = await testVoiceServices(
      agentRepository: agent,
      recorder: recorder,
      player: player,
      muted: true,
    );
    final repository = MockPropertyRepository();
    await tester.pumpTunnelPage(
      RepositoryProvider.value(value: services, child: const SurfacesPage()),
      sellerTunnelCubit: mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(id: 'property-id', ownerId: 'user-id'),
          rooms: [_living],
        ),
      ),
      propertyRepository: repository,
      goRouter: goRouter,
    );
  }

  Future<void> dictate(WidgetTester tester) async {
    levels.add(-20);
    await tester.pump();
    await tester.tap(find.text('J’ai fini'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('the microphone opens the rooms dictation', (tester) async {
    await pump(tester);
    // The description of a room shows in the table.
    expect(find.text('Ouvert sur la cuisine'), findsOneWidget);
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    expect(find.text('Dictée des pièces'), findsOneWidget);
    expect(find.text('PIÈCES DICTÉES'), findsOneWidget);
    await dictate(tester);
    expect(
      find.text('Bureau · Rez-de-chaussée · 9,0\u00a0m² · Parquet'),
      findsOneWidget,
    );
    expect(find.text('Fenêtre sur le jardin'), findsNWidgets(2));
    expect(find.text('47 m² habitables · 2 pièces'), findsOneWidget);
    // Silent dictation: no reply spoken.
    verifyNever(() => agent.speech(any()));

    await tester.ensureVisible(find.text('Terminer'));
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    expect(
      find.text('J’ai noté 2 pièces pour 47 m² habitables. Est-ce correct ?'),
      findsNWidgets(2),
    );
    verify(
      () => agent.roomsSummary(
        propertyId: 'property-id',
        rooms: any(named: 'rooms', that: hasLength(2)),
      ),
    ).called(1);
    await tester.ensureVisible(find.text('Oui'));
    await tester.tap(find.text('Oui'));
    await tester.pumpAndSettle();
    expect(find.text('Dictée des pièces'), findsNothing);
    expect(find.text('1 réponse ajoutée'), findsOneWidget);
    // The dictated room is in the table, tagged "Dicté".
    expect(find.text('Bureau'), findsOneWidget);
    expect(find.text('Dicté'), findsOneWidget);
  });

  testWidgets('"?dictee=1" (V5 "Dicter mes pièces") opens it at once', (
    tester,
  ) async {
    final goRouter = MockGoRouter();
    final state = _MockGoRouterState();
    when(() => state.uri).thenReturn(Uri.parse('/x?dictee=1'));
    when(() => goRouter.state).thenReturn(state);
    await pump(tester, goRouter: goRouter);
    await tester.pumpAndSettle();
    expect(find.text('Dictée des pièces'), findsOneWidget);
  });
}
