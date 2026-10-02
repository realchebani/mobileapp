import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/cubit/technical_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _house = Property(
  id: 'p',
  ownerId: 'u',
  propertyType: PropertyType.house,
  constructionYear: 1990,
  provenance: {'construction_year': 'document'},
);

const _turn = AgentTurn(
  turnId: 't1',
  transcript: 'construite en 1998, chauffage au gaz, piscine de 8 sur 4',
  reply: 'Noté.',
  patch: {
    'construction_year': 1998,
    'heating_systems': ['gaz'],
    'outdoor_equipment': ['piscine'],
    'pool_length_m': 8,
    'pool_width_m': 4,
  },
  facts: [AgentPill(field: 'construction_year', label: 'Construction 1998')],
);

void main() {
  group('TechnicalCubit voice', () {
    test('the draft is sent; a turn fills the form', () async {
      final cubit = TechnicalCubit(property: _house, today: DateTime(2026))
        ..livingAreaChanged('120');
      expect(cubit.voiceContext.draft['construction_year'], 1990);
      expect(cubit.voiceContext.draft['living_area_m2'], 120.0);
      cubit.submit(); // errors shown, kept after the turn
      await cubit.voiceTurnApplied(_turn);
      final state = cubit.state;
      expect(state.constructionYear, '1998');
      expect(state.livingArea, '120');
      expect(state.heatingSystems, [HeatingSystem.gas]);
      expect(state.poolDimensions, '8 × 4');
      expect(state.showErrors, isTrue);
      expect(state.dictated, {
        'construction_year',
        'heating_systems',
        'outdoor_equipment',
        'pool_length_m',
        'pool_width_m',
      });
      // The saved dossier is still the reference (provenance).
      expect(state.property, _house);
      expect(state.provenanceOf('construction_year'), Provenance.declared);
      // A turn without answers changes nothing.
      await cubit.voiceTurnApplied(
        const AgentTurn(turnId: 't2', transcript: '', reply: ''),
      );
      expect(cubit.state, state);
      await cubit.close();
    });
  });

  group('V4b voice sheet', () {
    late VoiceSheetMocks mocks;

    setUp(() => mocks = VoiceSheetMocks(turn: _turn));
    tearDown(() => mocks.dispose());

    testWidgets('the microphone opens the sheet; answers fill the form', (
      tester,
    ) async {
      final view = tester.view
        ..physicalSize = const Size(390, 3200)
        ..devicePixelRatio = 1;
      addTearDown(view.reset);
      await tester.pumpTunnelPage(
        RepositoryProvider.value(
          value: await mocks.services(),
          child: const TechnicalPage(),
        ),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: _house,
          ),
        ),
      );
      await tester.tap(find.byType(RealestyMicButton));
      await tester.pumpAndSettle();
      expect(find.text('Audit technique à la voix'), findsOneWidget);
      await mocks.speak(tester);
      expect(find.text('Construction 1998'), findsOneWidget);
      await mocks.close(tester);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.widgetWithText(
                  RealestyTextField,
                  'Année de construction',
                ),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '1998',
      );
      expect(find.text('Dicté'), findsWidgets);
      expect(mocks.lastContext()!.draft['construction_year'], 1990);
    });
  });
}
