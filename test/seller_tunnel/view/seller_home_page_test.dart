import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
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

  SellerTunnelState atStep(int step) => SellerTunnelState(
    status: SellerTunnelStatus.success,
    property: Property(id: 'p', ownerId: 'u', currentStep: step),
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
      verify(() => goRouter.go(AppRoutes.sellerOwners)).called(1);
    });

    testWidgets('resumes the audit at the current step', (tester) async {
      await tester.pumpTunnelPage(
        const SellerHomePage(),
        sellerTunnelCubit: mockSellerTunnelCubit(atStep(5)),
        goRouter: goRouter,
      );

      await tester.tap(find.text('Reprendre l’audit (étape 5/7)'));
      verify(() => goRouter.go(AppRoutes.sellerMethod)).called(1);
    });
  });
}
