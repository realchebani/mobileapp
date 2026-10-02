import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

/// EPIC-16 on V6.
void main() {
  late VoiceSheetMocks mocks;
  late MockPropertyRepository repository;

  setUpAll(
    () => registerFallbackValue(
      const LifestyleItem(
        propertyId: 'p',
        kind: LifestyleItemKind.asset,
        label: 'x',
      ),
    ),
  );

  setUp(() {
    VoiceFirstLauncher.resetSession();
    mocks = VoiceSheetMocks(
      turn: const AgentTurn(turnId: 't1', transcript: 'x', reply: 'Noté.'),
    );
    repository = MockPropertyRepository();
    when(() => repository.saveLifestyleItem(any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.single as LifestyleItem,
    );
  });
  tearDown(() => mocks.dispose());

  testWidgets('pre-filled items and noise; saved with their resolution', (
    tester,
  ) async {
    final view = tester.view
      ..physicalSize = const Size(390, 3600)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final cubit = mockSellerTunnelCubit(
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.house,
        ),
        pendingAnswers: [
          PendingAnswer(
            id: 'school',
            propertyId: 'p',
            targetStep: 'lifestyle',
            kind: PendingKind.lifestyleItem,
            value: {'kind': 'asset', 'label': 'École au bout de la rue'},
            label: 'École',
            quote: 'q',
            sourceStep: 'context',
          ),
          PendingAnswer(
            id: 'noise',
            propertyId: 'p',
            targetStep: 'lifestyle',
            kind: PendingKind.field,
            field: 'noise_level',
            value: 2,
            label: 'Bruit 2/10',
            quote: 'q',
            sourceStep: 'context',
          ),
          PendingAnswer(
            id: 'view',
            propertyId: 'p',
            targetStep: 'lifestyle',
            kind: PendingKind.field,
            field: 'overlooking',
            value: 'aucun',
            label: 'Aucun vis-à-vis',
            quote: 'q',
            sourceStep: 'context',
          ),
        ],
      ),
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await mocks.services(inputMode: VoiceInputMode.voice),
        child: const LifestylePage(),
      ),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
    );
    await tester.pumpAndSettle();
    expect(find.text('Parlez librement'), findsOneWidget);
    await mocks.close(tester);
    expect(find.text('École au bout de la rue'), findsOneWidget);
    expect(find.byType(ToConfirmTag), findsNWidgets(3));
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(savedStepPatch(cubit, SellerTunnelStep.lifestyle)['noise_level'], 2);
  });
}
