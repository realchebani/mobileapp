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
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  SellerTunnelState atStep(int step, {PropertyStatus? status}) =>
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'p',
          ownerId: 'u',
          currentStep: step,
          status: status ?? PropertyStatus.draft,
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
      expect(find.text('Design system'), findsNothing);
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

    testWidgets('opens the submitted dossier', (tester) async {
      await tester.pumpTunnelPage(
        const SellerHomePage(),
        sellerTunnelCubit: mockSellerTunnelCubit(
          atStep(8, status: PropertyStatus.submitted),
        ),
        goRouter: goRouter,
      );

      await tester.tap(find.text('Voir mon dossier envoyé'));
      verify(() => goRouter.go(AppRoutes.sellerSubmitted)).called(1);
    });

    testWidgets('signs out and opens the design system', (tester) async {
      final appBloc = MockAppBloc();
      when(() => appBloc.state).thenReturn(const AppState());
      await tester.pumpTunnelPage(
        const SellerHomePage(showDesignSystemLink: true),
        appBloc: appBloc,
        goRouter: goRouter,
      );

      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
      await tester.tap(find.text('Design system'));
      verify(() => goRouter.push<Object?>(AppRoutes.designSystem)).called(1);
    });
  });
}
