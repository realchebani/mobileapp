import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

const _house = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
);

void main() {
  late MockGoRouter goRouter;

  setUpAll(() {
    registerFallbackValue(DocumentSource.files);
    registerFallbackValue(DocumentKind.plan);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  group('technicalTurnHandler', () {
    test('saves the patch as declared', () async {
      final tunnel = mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: _house,
        ),
      );
      final handler = technicalTurnHandler(tunnel);
      await handler(const AgentTurn(turnId: 't', transcript: '', reply: ''));
      verifyNever(() => tunnel.save(any()));
      await handler(
        const AgentTurn(
          turnId: 't',
          transcript: '',
          reply: '',
          patch: {'construction_year': 1998},
        ),
      );
      verify(
        () => tunnel.save({
          'construction_year': 1998,
          'provenance': {'construction_year': 'declared'},
        }),
      ).called(1);
    });

    test('throws when the save failed', () async {
      final tunnel = mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: _house,
          saveStatus: SellerTunnelSaveStatus.failure,
        ),
      );
      await expectLater(
        technicalTurnHandler(tunnel)(
          const AgentTurn(
            turnId: 't',
            transcript: '',
            reply: '',
            patch: {'levels': 'r1'},
          ),
        ),
        throwsStateError,
      );
    });
  });

  testWidgets('without voice, redirects to V4b', (tester) async {
    await tester.pumpTunnelPage(const VoiceAuditPage(), goRouter: goRouter);
    await tester.pump();
    verify(() => goRouter.go(auditRoute(SellerTunnelStep.technical))).called(1);
  });

  testWidgets('with voice, starts listening after the consent', (tester) async {
    final recorder = MockVoiceRecorder();
    final player = MockVoicePlayer();
    when(recorder.requestPermission).thenAnswer((_) async => false);
    when(recorder.cancel).thenAnswer((_) async {});
    when(recorder.dispose).thenAnswer((_) async {});
    when(player.stop).thenAnswer((_) async {});
    when(player.dispose).thenAnswer((_) async {});
    final services = await testVoiceServices(
      recorder: recorder,
      player: player,
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: services,
        child: VoiceAuditPage(documentPicker: _MockDocumentPicker()),
      ),
      sellerTunnelCubit: mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: _house,
        ),
      ),
      goRouter: goRouter,
    );
    await tester.pumpAndSettle();
    verify(recorder.requestPermission).called(1);
    expect(find.text('Audit technique'), findsOneWidget);
    expect(find.textContaining('L’accès au micro est refusé'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
  });

  testWidgets('land goes to V4b even with voice', (tester) async {
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await testVoiceServices(),
        child: const VoiceAuditPage(),
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
      goRouter: goRouter,
    );
    await tester.pump();
    verify(() => goRouter.go(SellerTunnelStep.technical.routeFor('p')))
        .called(1);
  });

  test('waits for a save in progress before saving a turn', () async {
    const saving = SellerTunnelState(
      status: SellerTunnelStatus.success,
      property: _house,
      saveStatus: SellerTunnelSaveStatus.inProgress,
    );
    final tunnel = mockSellerTunnelCubit(saving);
    final states = StreamController<SellerTunnelState>();
    when(() => tunnel.stream).thenAnswer((_) => states.stream);
    final done = technicalTurnHandler(tunnel)(
      const AgentTurn(
        turnId: 't',
        transcript: '',
        reply: '',
        patch: {'levels': 'r1'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    verifyNever(() => tunnel.save(any()));
    when(
      () => tunnel.state,
    ).thenReturn(saving.copyWith(saveStatus: SellerTunnelSaveStatus.success));
    states.add(saving.copyWith(saveStatus: SellerTunnelSaveStatus.success));
    await done;
    verify(() => tunnel.save(any())).called(1);
    await states.close();
  });
}
