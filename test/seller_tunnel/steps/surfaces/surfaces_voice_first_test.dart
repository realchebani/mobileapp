import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

/// EPIC-16 on V5c.
void main() {
  late VoiceSheetMocks mocks;
  late MockPropertyRepository repository;

  setUpAll(
    () => registerFallbackValue(
      const Room(propertyId: 'p', name: 'x', areaM2: 1),
    ),
  );

  setUp(() {
    VoiceFirstLauncher.resetSession();
    mocks = VoiceSheetMocks(
      turn: const AgentTurn(turnId: 't1', transcript: 'x', reply: 'Noté.'),
    );
    when(
      () => mocks.agent.roomsSummary(
        propertyId: any(named: 'propertyId'),
        rooms: any(named: 'rooms'),
      ),
    ).thenAnswer(
      (_) async => const AgentTurn(turnId: 'ts', transcript: '', reply: 'OK'),
    );
    repository = MockPropertyRepository();
    when(() => repository.saveRoom(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as Room,
    );
  });
  tearDown(() => mocks.dispose());

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    List<Room> rooms = const [],
    List<PendingAnswer> pending = const [],
  }) async {
    final view = tester.view
      ..physicalSize = const Size(390, 2400)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: const Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.apartment,
        ),
        rooms: rooms,
        pendingAnswers: pending,
      ),
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await mocks.services(inputMode: VoiceInputMode.voice),
        child: const SurfacesPage(),
      ),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('no room yet: the dictation opens by itself', (tester) async {
    await pump(tester);
    expect(find.text('Dictée des pièces'), findsOneWidget);
    await tester.tap(find.text('Écrire plutôt'));
    await tester.pumpAndSettle();
    expect(find.text('Dictée des pièces'), findsNothing);
  });

  testWidgets('a room said elsewhere joins the table « À confirmer »', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      rooms: const [
        Room(
          id: 'r0',
          propertyId: 'p',
          name: 'Séjour',
          areaM2: 30,
          isMain: true,
          photosCount: 1,
        ),
      ],
      pending: const [
        PendingAnswer(
          id: 'kitchen',
          propertyId: 'p',
          targetStep: 'rooms',
          kind: PendingKind.room,
          value: {'name': 'Cuisine', 'area_m2': 12, 'kind': 'kitchen'},
          label: 'Cuisine · 12 m²',
          quote: 'q',
          sourceStep: 'context',
        ),
      ],
    );
    // Rooms already there: no dictation by itself.
    expect(find.text('Dictée des pièces'), findsNothing);
    expect(find.text('Cuisine'), findsOneWidget);
    expect(find.byType(ToConfirmTag), findsOneWidget);
    expect(find.textContaining('dont 12'), findsOneWidget);
    await tester.tap(find.text('C’est correct, continuer'));
    await tester.pumpAndSettle();
    final resolve =
        verify(
              () => cubit.saveStepAndContinue(
                SellerTunnelStep.surfaces,
                any(),
                resolve: captureAny(named: 'resolve'),
              ),
            ).captured.single
            as Map<PendingResolution, List<String>>;
    expect(resolve, {
      PendingResolution.continueTapped: ['kitchen'],
    });
  });

  testWidgets('totals of rooms all read on a plan are extracted', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      rooms: const [
        Room(
          id: 'r0',
          propertyId: 'p',
          name: 'Séjour',
          areaM2: 30,
          isMain: true,
          photosCount: 1,
          source: RoomSource.plan,
        ),
        Room(
          id: 'r1',
          propertyId: 'p',
          name: 'Garage',
          areaM2: 15,
          isAnnex: true,
          source: RoomSource.plan,
        ),
      ],
    );
    await tester.tap(find.text('C’est correct, continuer'));
    await tester.pumpAndSettle();
    final patch =
        verify(
              () => cubit.saveStepAndContinue(
                SellerTunnelStep.surfaces,
                captureAny(),
                resolve: any(named: 'resolve'),
              ),
            ).captured.single
            as Map<String, Object?>;
    final sources = patch['field_sources']! as Map;
    expect((sources['living_area_m2'] as Map)['s'], 'extrait');
    expect((sources['annex_area_m2'] as Map)['s'], 'extrait');
  });
}
