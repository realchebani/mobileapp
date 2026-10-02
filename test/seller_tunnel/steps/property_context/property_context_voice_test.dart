import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/cubit/property_context_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _property = Property(
  id: 'p',
  ownerId: 'u',
  propertyType: PropertyType.house,
  purchaseYear: 2010,
);

AgentEntityChange _estimate(
  AgentEntityOp op,
  String target, [
  Map<String, Object?> values = const {},
]) => AgentEntityChange(
  entity: AgentEntity.previousEstimate,
  op: op,
  target: target,
  label: 'x',
  values: values,
);

AgentTurn _turn({
  Map<String, Object?> patch = const {},
  List<AgentEntityChange> ops = const [],
}) => AgentTurn(
  turnId: 't',
  transcript: '',
  reply: '',
  patch: patch,
  entityOps: ops,
);

void main() {
  PropertyContextCubit build({
    Property property = _property,
    List<PreviousEstimate> estimates = const [],
  }) => PropertyContextCubit(
    propertyRepository: MockPropertyRepository(),
    property: property,
    estimates: estimates,
    today: DateTime(2026, 10, 2),
  );

  group('PropertyContextCubit voice', () {
    test('the answers said fill the form', () async {
      final cubit = build();
      expect(cubit.voiceContext.draft, {
        'property_type': 'maison',
        'purchase_year': 2010,
        'purchase_price_eur': null,
        'self_built': null,
        'sale_reason': null,
        'previously_estimated': null,
      });
      expect(cubit.voiceContext.estimates, isEmpty);
      await cubit.voiceTurnApplied(
        _turn(
          patch: {
            'purchase_year': 2012,
            'purchase_price_eur': 320000,
            'self_built': false,
            'sale_reason': 'mutation',
            'previously_estimated': false,
          },
        ),
      );
      var state = cubit.state;
      expect(state.purchaseYear, '2012');
      expect(state.purchasePrice, '320 000');
      expect(state.selfBuilt, isFalse);
      expect(state.saleReason, SaleReason.relocation);
      expect(state.previouslyEstimated, isFalse);
      expect(state.estimates, isEmpty);
      expect(state.dictated, contains('purchase_price_eur'));
      // A confirmed type change with its precision.
      await cubit.voiceTurnApplied(
        _turn(
          patch: {
            'property_type': 'stationnement',
            'parking_kind': 'box',
            'land_kind': 'constructible',
            'commercial_use': 'Boutique',
            'units_count': 4,
            'property_type_other': 'Grange',
          },
        ),
      );
      state = cubit.state;
      expect(state.propertyType, PropertyType.parking);
      expect(state.parkingKind, ParkingKind.box);
      expect(state.landKind, LandKind.buildable);
      expect(state.commercialUse, 'Boutique');
      expect(state.unitsCount, '4');
      expect(state.propertyTypeOther, 'Grange');
      // Cleared answers.
      await cubit.voiceTurnApplied(
        _turn(
          patch: {
            'parking_kind': null,
            'land_kind': null,
            'sale_reason': null,
            'property_type_other': null,
          },
        ),
      );
      state = cubit.state;
      expect(state.parkingKind, isNull);
      expect(state.landKind, isNull);
      expect(state.saleReason, isNull);
      expect(state.propertyTypeOther, '');
      await cubit.close();
    });

    test('estimates: fill the empty card, add, update, remove', () async {
      final cubit = build()
        ..previouslyEstimatedChanged(previouslyEstimated: true);
      expect(cubit.voiceContext.estimates, const [AgentEstimate(ref: 'E1')]);
      await cubit.voiceTurnApplied(
        _turn(
          ops: [
            _estimate(AgentEntityOp.create, 'new', {
              'price_eur': 300000,
              'estimated_month': '2024-03-01',
              'agency_name': 'Century 21',
            }),
            _estimate(AgentEntityOp.create, 'new', {'price_eur': 280000}),
          ],
        ),
      );
      var estimates = cubit.state.estimates;
      expect(estimates, hasLength(2));
      expect(estimates.first.price, '300 000');
      expect(estimates.first.month, '03/2024');
      expect(estimates.first.agency, 'Century 21');
      expect(estimates.last.price, '280 000');
      expect(cubit.state.previouslyEstimated, isTrue);
      expect(
        cubit.state.dictated.where((d) => d.startsWith('estimate:')),
        hasLength(2),
      );
      expect(cubit.voiceContext.estimates.first.month, DateTime(2024, 3));
      final firstKey = estimates.first.key;
      await cubit.voiceTurnApplied(
        _turn(
          ops: [
            _estimate(AgentEntityOp.update, 'E1', {'agency_name': 'Orpi'}),
            _estimate(AgentEntityOp.delete, 'E2'),
            _estimate(AgentEntityOp.update, 'E9', {'price_eur': 1}),
            const AgentEntityChange(
              entity: AgentEntity.room,
              op: AgentEntityOp.create,
              target: 'new',
              label: 'x',
            ),
          ],
        ),
      );
      estimates = cubit.state.estimates;
      expect(estimates, hasLength(1));
      expect(estimates.single.agency, 'Orpi');
      expect(estimates.single.price, '300 000');
      // A new card key: the card shows the dictated values.
      expect(estimates.single.key, isNot(firstKey));
      await cubit.close();
    });

    test('"oui" without an estimate opens a first card', () async {
      final cubit = build();
      await cubit.voiceTurnApplied(
        _turn(patch: {'previously_estimated': true}),
      );
      expect(cubit.state.estimates, hasLength(1));
      expect(cubit.state.estimates.single.price, isEmpty);
      expect(cubit.acceptsVoice, isTrue);
      await cubit.close();
    });
  });

  group('V3 voice sheet', () {
    late VoiceSheetMocks mocks;

    setUp(
      () => mocks = VoiceSheetMocks(
        turn: const AgentTurn(
          turnId: 't1',
          transcript: 'achetée en 2012',
          reply: 'Noté.',
          patch: {'purchase_year': 2012},
          facts: [AgentPill(field: 'purchase_year', label: 'Achat 2012')],
        ),
      ),
    );
    tearDown(() => mocks.dispose());

    testWidgets('the microphone opens the sheet; the year is filled', (
      tester,
    ) async {
      final view = tester.view
        ..physicalSize = const Size(390, 2400)
        ..devicePixelRatio = 1;
      addTearDown(view.reset);
      await tester.pumpTunnelPage(
        RepositoryProvider.value(
          value: await mocks.services(),
          child: const PropertyContextPage(),
        ),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: _property,
          ),
        ),
      );
      await tester.tap(find.byType(RealestyMicButton));
      await tester.pumpAndSettle();
      expect(find.text('Contexte à la voix'), findsOneWidget);
      await mocks.speak(tester);
      await mocks.close(tester);
      expect(find.text('2012'), findsOneWidget);
      expect(find.text('Dicté'), findsOneWidget);
      expect(mocks.lastContext()!.draft['purchase_year'], 2010);
    });
  });
}
