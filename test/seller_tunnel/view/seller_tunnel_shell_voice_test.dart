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
  testWidgets('V3 opens the voice audit (V4) when voice is available', (
    tester,
  ) async {
    final goRouter = MockGoRouter();
    final routerState = _MockGoRouterState();
    when(() => routerState.matchedLocation).thenReturn(AppRoutes.sellerContext);
    when(() => goRouter.state).thenReturn(routerState);
    when(() => goRouter.go(any())).thenReturn(null);
    final cubit = mockSellerTunnelCubit();
    const loaded = SellerTunnelState(
      status: SellerTunnelStatus.success,
      property: testProperty,
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
    verify(() => goRouter.go(AppRoutes.sellerVoiceAudit)).called(1);
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
