import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Property property,
    MockGoRouter go,
  ) async {
    usePhoneSurface();
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await testVoiceServices(),
        child: const TechnicalPage(),
      ),
      sellerTunnelCubit: mockSellerTunnelCubit(
        SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: property,
        ),
      ),
      goRouter: go,
    );
  }

  testWidgets('the microphone opens the voice audit (V4)', (tester) async {
    final goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    await pump(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.house),
      goRouter,
    );
    expect(find.text('Répondez à la voix ou à l’écran'), findsOneWidget);
    await tester.tap(find.byType(RealestyMicButton));
    verify(() => goRouter.go(AppRoutes.sellerVoiceAudit)).called(1);
  });

  testWidgets('no voice audit for land', (tester) async {
    await pump(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
      MockGoRouter(),
    );
    expect(find.byType(RealestyMicButton), findsNothing);
  });
}
