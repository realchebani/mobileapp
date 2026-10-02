import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/location/cubit/location_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/location/data/device_locator.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';
import 'location_fixtures.dart';

class _MockDeviceLocator extends Mock implements DeviceLocator;

const _situations = AgentTurn(
  turnId: 't1',
  transcript: 'il y a un droit de passage et un puits commun',
  reply: 'Noté.',
  patch: {
    'special_situations': ['autre', 'servitude_passage'],
    'special_situation_other': 'Puits commun',
  },
  facts: [
    AgentPill(field: 'special_situations', label: 'Servitude de passage'),
  ],
);

void main() {
  late MockGeoRepository geo;

  setUp(() {
    geo = MockGeoRepository();
    when(() => geo.searchAddresses(any()))
        .thenAnswer((_) async => [testAddress]);
  });

  group('LocationCubit voice', () {
    test('situations and their precision; the draft is sent', () async {
      final cubit = LocationCubit(
        geoRepository: geo,
        propertyRepository: MockPropertyRepository(),
        deviceLocator: _MockDeviceLocator(),
        property: testProperty,
        parcels: const [],
      )..situationToggled(SpecialSituation.none, selected: true);
      expect(cubit.voiceContext.draft, {
        'special_situations': ['aucune'],
        'special_situation_other': null,
      });
      await cubit.voiceTurnApplied(_situations);
      expect(cubit.state.situations, [
        SpecialSituation.rightOfWay,
        SpecialSituation.other,
      ]);
      expect(cubit.state.otherSituation, 'Puits commun');
      expect(cubit.state.dictated, {
        'special_situations',
        'special_situation_other',
      });
      expect(
        cubit.voiceContext.draft['special_situation_other'],
        'Puits commun',
      );
      // Nothing said about them: unchanged.
      await cubit.voiceTurnApplied(
        const AgentTurn(turnId: 't2', transcript: '', reply: ''),
      );
      expect(cubit.state.otherSituation, 'Puits commun');
      expect(cubit.acceptsVoice, isTrue);
      await cubit.close();
    });
  });

  group('V2 voice', () {
    late VoiceSheetMocks mocks;

    setUp(
      () => mocks = VoiceSheetMocks(
        turn: _situations,
        transcript: '12 rue des Lilas Lyon',
      ),
    );
    tearDown(() => mocks.dispose());

    Future<void> pump(WidgetTester tester) async {
      final view = tester.view
        ..physicalSize = const Size(390, 2400)
        ..devicePixelRatio = 1;
      addTearDown(view.reset);
      await tester.pumpTunnelPage(
        RepositoryProvider.value(
          value: await mocks.services(),
          child: LocationPage(
            deviceLocator: _MockDeviceLocator(),
            tileBuilder: testTile,
          ),
        ),
        geoRepository: geo,
      );
    }

    testWidgets('the microphone answers the special situations', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byType(RealestyMicButton));
      await tester.pumpAndSettle();
      expect(find.text('Servitudes à la voix'), findsOneWidget);
      await mocks.speak(tester);
      await mocks.close(tester);
      expect(find.text('Puits commun'), findsOneWidget);
      expect(find.text('Dicté'), findsOneWidget);
    });

    testWidgets('the address is dictated into the search field', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Dicter l’adresse'));
      await tester.pumpAndSettle();
      expect(find.text('Dictez l’adresse'), findsOneWidget);
      mocks.levels.add(-20);
      await tester.pump();
      await tester.tap(find.text('J’ai fini'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Dictez l’adresse'), findsNothing);
      expect(find.text('12 rue des Lilas Lyon'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      verify(() => geo.searchAddresses('12 rue des Lilas Lyon')).called(1);
      verify(
        () => mocks.agent.transcribe(
          propertyId: 'property-id',
          step: AgentStep.location,
          audio: any(named: 'audio'),
          duration: any(named: 'duration'),
          format: any(named: 'format'),
          dictation: true,
        ),
      ).called(1);
      // Nothing goes to the agent.
      verifyNever(
        () => mocks.agent.turn(
          propertyId: any(named: 'propertyId'),
          step: any(named: 'step'),
          turnId: any(named: 'turnId'),
          assetLabels: any(named: 'assetLabels'),
          watchPointLabels: any(named: 'watchPointLabels'),
          context: any(named: 'context'),
          undoneTurnIds: any(named: 'undoneTurnIds'),
        ),
      );
    });

    testWidgets('a closed dictation changes nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Dicter l’adresse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      verifyNever(() => geo.searchAddresses(any()));
    });
  });
}
