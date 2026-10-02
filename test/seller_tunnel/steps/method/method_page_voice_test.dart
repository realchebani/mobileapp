import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    SellerTunnelSaveStatus saveStatus = SellerTunnelSaveStatus.success,
    int currentStep = 4,
    bool voice = true,
    VoiceInputMode mode = VoiceInputMode.text,
  }) async {
    usePhoneSurface();
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        saveStatus: saveStatus,
        property: Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.house,
          currentStep: currentStep,
        ),
      ),
    );
    await tester.pumpTunnelPage(
      voice
          ? RepositoryProvider.value(
              value: await testVoiceServices(inputMode: mode),
              child: const MethodPage(),
            )
          : const MethodPage(),
      sellerTunnelCubit: cubit,
      goRouter: goRouter,
    );
    return cubit;
  }

  testWidgets('"Dicter mes pièces" saves the method and opens the '
      'dictation', (tester) async {
    final cubit = await pump(tester);
    expect(
      find.text(
        'Décrivez chaque pièce à voix haute : nom, surface, niveau, '
        'sol, vitrage.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Dicter mes pièces'));
    await tester.pumpAndSettle();
    verify(
      () => cubit.save({
        PropertyColumns.measurementMethod: MeasurementMethod.manual,
        PropertyColumns.currentStep: SellerTunnelStep.surfaces.number,
      }),
    ).called(1);
    verify(() => goRouter.go('/vendeur/biens/p/audit/surfaces?dictee=1'))
        .called(1);
  });

  testWidgets('a later step is kept; a failed save stays on V5', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      currentStep: 6,
      saveStatus: SellerTunnelSaveStatus.failure,
    );
    await tester.tap(find.text('Dicter mes pièces'));
    await tester.pumpAndSettle();
    verify(
      () => cubit.save({
        PropertyColumns.measurementMethod: MeasurementMethod.manual,
      }),
    ).called(1);
    verifyNever(() => goRouter.go(any()));
  });

  testWidgets('no dictation without voice', (tester) async {
    await pump(tester, voice: false);
    expect(find.text('Dicter mes pièces'), findsNothing);
  });

  testWidgets('EPIC-16: in the voice mode « Dicter mes pièces » comes first', (
    tester,
  ) async {
    await pump(tester, mode: VoiceInputMode.voice);
    expect(find.text('Recommandé'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Dicter mes pièces')).dy,
      lessThan(tester.getTopLeft(find.text('Saisir manuellement')).dy),
    );
    await tester.tap(find.text('Dicter mes pièces'));
    await tester.pumpAndSettle();
    verify(() => goRouter.go(any())).called(1);
  });
}
