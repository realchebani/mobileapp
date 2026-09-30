import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  group(ProvisionalStepView, () {
    testWidgets('saves and continues, or goes back', (tester) async {
      final cubit = mockSellerTunnelCubit();
      await tester.pumpTunnelPage(
        const ProvisionalStepView(step: SellerTunnelStep.location),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );

      expect(find.byType(TunnelHeader), findsOneWidget);
      expect(find.text('Étape 2 · Cadastre'), findsOneWidget);
      await tester.tap(find.text('Continuer'));
      verify(() => cubit.saveAndContinue(SellerTunnelStep.location)).called(1);

      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(AppRoutes.sellerOwners)).called(1);
    });

    testWidgets('goes back to the seller space from the first step', (
      tester,
    ) async {
      await tester.pumpTunnelPage(
        const ProvisionalStepView(step: SellerTunnelStep.owners),
        goRouter: goRouter,
      );
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(AppRoutes.seller)).called(1);
    });

    testWidgets('shows a loading action while saving', (tester) async {
      await tester.pumpTunnelPage(
        const ProvisionalStepView(step: SellerTunnelStep.owners),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: testProperty,
            saveStatus: SellerTunnelSaveStatus.inProgress,
          ),
        ),
      );
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).isLoading,
        isTrue,
      );
    });

    testWidgets('shows the submitted screen without header', (tester) async {
      await tester.pumpTunnelPage(
        const ProvisionalStepView(step: SellerTunnelStep.submitted),
        goRouter: goRouter,
      );

      expect(find.byType(TunnelHeader), findsNothing);
      expect(find.text('Dossier envoyé'), findsOneWidget);
      await tester.tap(find.text('Retour à mon dossier'));
      verify(() => goRouter.go(AppRoutes.seller)).called(1);
    });
  });
}
