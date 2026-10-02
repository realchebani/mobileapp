import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

class _MockGoRouterState extends Mock implements GoRouterState;

void main() {
  Future<MockGoRouter> continueFromV3(
    WidgetTester tester,
    Property property,
  ) async {
    final goRouter = MockGoRouter();
    final routerState = _MockGoRouterState();
    when(() => routerState.matchedLocation).thenReturn(AppRoutes.sellerContext);
    when(() => goRouter.state).thenReturn(routerState);
    when(() => goRouter.go(any())).thenReturn(null);
    final cubit = mockSellerTunnelCubit();
    final loaded = SellerTunnelState(
      status: SellerTunnelStatus.success,
      property: property,
    );
    whenListen(
      cubit,
      Stream.value(
        loaded.copyWith(
          saveStatus: SellerTunnelSaveStatus.success,
          nextStep: SellerTunnelStep.technical,
          continuedFrom: SellerTunnelStep.context,
        ),
      ),
      initialState: loaded,
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await testVoiceServices(),
        child: const SellerTunnelGate(child: Text('child')),
      ),
      sellerTunnelCubit: cubit,
      goRouter: goRouter,
    );
    await tester.pump();
    return goRouter;
  }

  testWidgets('V3 opens the voice audit (V4) when voice is available', (
    tester,
  ) async {
    final goRouter = await continueFromV3(tester, testProperty);
    verify(() => goRouter.go(AppRoutes.sellerVoiceAudit)).called(1);
  });

  testWidgets('V3 opens V4b for land', (tester) async {
    final goRouter = await continueFromV3(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
    );
    verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(1);
  });

  test('a sent dossier sends the voice audit to V8', () {
    const sent = SellerTunnelState(
      property: Property(
        id: 'p',
        ownerId: 'u',
        status: PropertyStatus.submitted,
      ),
    );
    expect(
      sent.lockRedirect(AppRoutes.sellerVoiceAudit),
      AppRoutes.sellerSubmitted,
    );
    expect(sent.lockRedirect('/vendeur/autre'), isNull);
  });
}
