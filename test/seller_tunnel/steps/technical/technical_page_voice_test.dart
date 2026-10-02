import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _valid = Property(
  id: 'p',
  ownerId: 'u',
  propertyType: PropertyType.house,
  constructionYear: 1998,
  livingAreaM2: 100,
  roomsCount: 1,
  bedroomsCount: 0,
  levels: PropertyLevels.singleStorey,
  heatingSystems: [HeatingSystem.gas],
);

void main() {
  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester,
    Property property, {
    SellerTunnelSaveStatus saveStatus = SellerTunnelSaveStatus.idle,
  }) async {
    final view = tester.view
      ..physicalSize = const Size(390, 3000)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: property,
        saveStatus: saveStatus,
      ),
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await testVoiceServices(),
        child: const TechnicalPage(),
      ),
      sellerTunnelCubit: cubit,
      goRouter: goRouter,
    );
    return cubit;
  }

  Future<void> typeYear(WidgetTester tester) => tester.enterText(
    find.descendant(
      of: find.widgetWithText(RealestyTextField, 'Année de construction'),
      matching: find.byType(TextField),
    ),
    '1999',
  );

  testWidgets('the microphone opens V4 (nothing to save)', (tester) async {
    final tunnel = await pump(tester, _valid);
    expect(find.text('Répondez à la voix ou à l’écran'), findsOneWidget);
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    verifyNever(() => tunnel.save(any()));
    verify(() => goRouter.go('/vendeur/biens/p/audit/technique-vocal'))
        .called(1);
  });

  testWidgets('typed answers are saved before opening V4', (tester) async {
    final tunnel = await pump(tester, _valid);
    await typeYear(tester);
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    verify(() => tunnel.save(any())).called(1);
    verify(() => goRouter.go('/vendeur/biens/p/audit/technique-vocal'))
        .called(1);
  });

  testWidgets('a failed save stays on V4b', (tester) async {
    final tunnel = await pump(
      tester,
      _valid,
      saveStatus: SellerTunnelSaveStatus.failure,
    );
    await typeYear(tester);
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    verify(() => tunnel.save(any())).called(1);
    verifyNever(() => goRouter.go(any()));
  });

  testWidgets('invalid answers are shown instead', (tester) async {
    await pump(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.house),
    );
    await tester.tap(find.byType(RealestyMicButton));
    await tester.pumpAndSettle();
    verifyNever(() => goRouter.go(any()));
    expect(find.text('Indiquez l’année de construction'), findsOneWidget);
  });

  testWidgets('no voice audit for land', (tester) async {
    await pump(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
    );
    expect(find.byType(RealestyMicButton), findsNothing);
  });
}
