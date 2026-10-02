import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

PendingAnswer _pending(
  String id,
  PendingKind kind,
  Object? value, {
  String? field,
}) => PendingAnswer(
  id: id,
  propertyId: 'p',
  targetStep: 'context',
  kind: kind,
  field: field,
  value: value,
  label: id,
  quote: 'q',
  sourceStep: 'technical',
);

/// EPIC-16 on V3.
void main() {
  late VoiceSheetMocks mocks;
  late MockPropertyRepository repository;

  setUpAll(
    () => registerFallbackValue(
      const PreviousEstimate(propertyId: 'p', priceEur: 1),
    ),
  );

  setUp(() {
    VoiceFirstLauncher.resetSession();
    mocks = VoiceSheetMocks(
      turn: const AgentTurn(turnId: 't1', transcript: 'x', reply: 'Noté.'),
    );
    repository = MockPropertyRepository();
    when(() => repository.savePreviousEstimate(any()))
        .thenAnswer((invocation) async {
          final estimate =
              invocation.positionalArguments.single as PreviousEstimate;
          return PreviousEstimate(
            id: 'e1',
            propertyId: estimate.propertyId,
            priceEur: estimate.priceEur,
            fieldSources: estimate.fieldSources,
          );
        });
  });
  tearDown(() => mocks.dispose());

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester,
    Property property,
    List<PendingAnswer> pending,
  ) async {
    final view = tester.view
      ..physicalSize = const Size(390, 3200)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: property,
        pendingAnswers: pending,
      ),
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await mocks.services(inputMode: VoiceInputMode.voice),
        child: const PropertyContextPage(),
      ),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('pre-filled answers and estimate, saved with their resolution', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.house),
      [
        _pending('year', PendingKind.field, 2012, field: 'purchase_year'),
        _pending('built', PendingKind.field, false, field: 'self_built'),
        _pending('estimate', PendingKind.previousEstimate, const {
          'price_eur': 300000,
        }),
      ],
    );
    expect(find.text('Contexte à la voix'), findsOneWidget);
    await mocks.close(tester);
    expect(find.byType(ToConfirmTag), findsNWidgets(3));
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    final captured = verify(
      () => cubit.saveStepAndContinue(
        SellerTunnelStep.context,
        captureAny(),
        resolve: captureAny(named: 'resolve'),
      ),
    ).captured;
    expect((captured.first as Map)['purchase_year'], 2012);
    final resolve = captured.last as Map<PendingResolution, List<String>>;
    expect(resolve, {
      PendingResolution.continueTapped: ['year', 'built', 'estimate'],
    });
  });

  testWidgets('the land and parking answers carry their tag', (tester) async {
    await pump(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
      [
        _pending(
          'land',
          PendingKind.field,
          'constructible',
          field: 'land_kind',
        ),
      ],
    );
    await mocks.close(tester);
    expect(find.byType(ToConfirmTag), findsOneWidget);
  });

  testWidgets('parking', (tester) async {
    await pump(
      tester,
      const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.parking),
      [_pending('kind', PendingKind.field, 'box', field: 'parking_kind')],
    );
    await mocks.close(tester);
    expect(find.byType(ToConfirmTag), findsOneWidget);
  });
}
