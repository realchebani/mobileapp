import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  SellerTunnelState atStep(int step, {PropertyType? type}) => SellerTunnelState(
    status: SellerTunnelStatus.success,
    property: Property(
      id: 'p',
      ownerId: 'u',
      currentStep: step,
      propertyType: type,
    ),
  );

  group(SellerHomePage, () {
    testWidgets('starts the audit', (tester) async {
      await tester.pumpTunnelPage(
        const SellerHomePage(),
        sellerTunnelCubit: mockSellerTunnelCubit(atStep(1)),
        goRouter: goRouter,
      );

      expect(find.text('Mon dossier vendeur'), findsOneWidget);
      // Signing out moved to the "Compte" tab.
      expect(find.text('Se déconnecter'), findsNothing);
      await tester.tap(find.text('Commencer l’audit'));
      verify(() => goRouter.go(SellerTunnelStep.owners.routeFor('p')))
          .called(1);
    });

    testWidgets('resumes the audit at the current step', (tester) async {
      await tester.pumpTunnelPage(
        const SellerHomePage(),
        sellerTunnelCubit: mockSellerTunnelCubit(atStep(5)),
        goRouter: goRouter,
      );

      await tester.tap(find.text('Reprendre l’audit (étape 5/7)'));
      verify(() => goRouter.go(SellerTunnelStep.method.routeFor('p')))
          .called(1);
    });

    testWidgets(
      'counts the steps of the type, with a back arrow and a footer',
      (tester) async {
        var back = 0;
        await tester.pumpTunnelPage(
          SellerHomePage(onBack: () => back++, footer: const Text('footer')),
          sellerTunnelCubit: mockSellerTunnelCubit(
            atStep(5, type: PropertyType.parking),
          ),
          goRouter: goRouter,
        );

        expect(find.text('footer'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Mes biens'));
        expect(back, 1);
        await tester.tap(find.text('Reprendre l’audit (étape 5/5)'));
        verify(() => goRouter.go(SellerTunnelStep.documents.routeFor('p')))
            .called(1);
      },
    );
  });
}
