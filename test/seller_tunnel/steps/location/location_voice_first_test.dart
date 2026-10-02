import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/location/data/device_locator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';
import 'location_fixtures.dart';

class _MockDeviceLocator extends Mock implements DeviceLocator;

/// EPIC-16 on V2: the address dictation opens by itself, then the
/// situations sheet once the parcels are confirmed.
void main() {
  late VoiceSheetMocks mocks;
  late MockGeoRepository geo;

  setUpAll(() => registerFallbackValue(testPoint));

  setUp(() {
    VoiceFirstLauncher.resetSession();
    mocks = VoiceSheetMocks(
      turn: const AgentTurn(turnId: 't1', transcript: 'x', reply: 'Noté.'),
      transcript: '12 rue de la Colombe',
    );
    geo = MockGeoRepository();
    when(() => geo.searchAddresses(any())).thenAnswer((_) async => []);
    when(() => geo.parcelAt(any())).thenAnswer((_) async => testParcel);
  });
  tearDown(() => mocks.dispose());

  Future<void> pump(WidgetTester tester, SellerTunnelState state) async {
    final view = tester.view
      ..physicalSize = const Size(390, 2400)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await mocks.services(inputMode: VoiceInputMode.voice),
        child: LocationPage(
          deviceLocator: _MockDeviceLocator(),
          tileBuilder: testTile,
        ),
      ),
      sellerTunnelCubit: mockSellerTunnelCubit(state),
      geoRepository: geo,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a new dossier: the address opens in dictation', (tester) async {
    await pump(
      tester,
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: testProperty,
      ),
    );
    expect(find.text('Dictez l’adresse'), findsOneWidget);
    await mocks.speak(tester);
    await tester.pumpAndSettle();
    expect(find.text('Dictez l’adresse'), findsNothing);
    expect(find.text('12 rue de la Colombe'), findsOneWidget);
  });

  testWidgets('the parcels confirmed, the situations sheet opens once', (
    tester,
  ) async {
    await pump(
      tester,
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'property-id',
          ownerId: 'user-id',
          addressLabel: testAddress.label,
          addressBanId: testAddress.id,
          lat: testPoint.lat,
          lng: testPoint.lng,
        ),
        parcels: [
          PropertyParcel(
            id: 'row-98',
            propertyId: 'property-id',
            idu: testParcel.idu,
            section: 'AB',
            numero: '0098',
            areaM2: 540,
            geometry: testParcel.geometry,
          ),
        ],
      ),
    );
    // An address but unconfirmed parcels: the form.
    expect(find.text('Servitudes à la voix'), findsNothing);
    await tester.ensureVisible(find.text('Oui, c’est correct'));
    await tester.tap(find.text('Oui, c’est correct'));
    await tester.pumpAndSettle();
    expect(find.text('Servitudes à la voix'), findsOneWidget);
    await mocks.close(tester);
    // Once per visit.
    await tester.ensureVisible(find.text('Modifier / ajouter'));
    await tester.tap(find.text('Modifier / ajouter'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Oui, c’est correct'));
    await tester.tap(find.text('Oui, c’est correct'));
    await tester.pumpAndSettle();
    expect(find.text('Servitudes à la voix'), findsNothing);
  });

  testWidgets('a confirmed address on arrival: the situations sheet', (
    tester,
  ) async {
    await pump(
      tester,
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'property-id',
          ownerId: 'user-id',
          addressLabel: testAddress.label,
          lat: testPoint.lat,
          lng: testPoint.lng,
          parcelConfirmed: true,
        ),
        parcels: [
          PropertyParcel(
            id: 'row-98',
            propertyId: 'property-id',
            idu: testParcel.idu,
            geometry: testParcel.geometry,
          ),
        ],
      ),
    );
    expect(find.text('Servitudes à la voix'), findsOneWidget);
    await mocks.close(tester);
  });
}
