import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/location/data/device_locator.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/parcel_card.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/parcel_map.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';
import 'location_fixtures.dart';

class _MockDeviceLocator extends Mock implements DeviceLocator;

const _nbsp = ' ';

/// A dossier whose address and parcel are saved.
final _located = SellerTunnelState(
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
);

Finder _addressInput() => find.descendant(
  of: find.widgetWithText(RealestyTextField, 'Adresse du bien'),
  matching: find.byType(TextField),
);

void main() {
  late MockGeoRepository geo;
  late MockPropertyRepository properties;
  late _MockDeviceLocator locator;

  setUpAll(() async {
    await loadRealestyFonts();
    registerFallbackValue(testPoint);
    registerFallbackValue(
      const PropertyParcel(propertyId: 'property-id', idu: 'x'),
    );
  });

  setUp(() {
    geo = MockGeoRepository();
    properties = MockPropertyRepository();
    locator = _MockDeviceLocator();
    when(() => geo.parcelAt(any())).thenAnswer((_) async => testParcel);
    when(() => geo.searchAddresses(any()))
        .thenAnswer((_) async => [testAddress]);
    when(() => geo.reverseGeocode(any())).thenAnswer((_) async => testAddress);
    when(locator.currentPosition).thenAnswer((_) async => testPoint);
    when(() => properties.saveParcel(any())).thenAnswer((invocation) async {
      final parcel = invocation.positionalArguments.single as PropertyParcel;
      return PropertyParcel(
        id: 'new-${parcel.idu}',
        propertyId: parcel.propertyId,
        idu: parcel.idu,
      );
    });
    when(() => properties.deleteParcel(any())).thenAnswer((_) async {});
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    SellerTunnelState? state,
    Stream<SellerTunnelState>? states,
    MockGoRouter? goRouter,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final view = tester.view
      ..physicalSize = Size(width, 2000)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final initial =
        state ??
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: testProperty,
        );
    final cubit = mockSellerTunnelCubit(initial);
    if (states != null) whenListen(cubit, states, initialState: initial);
    await tester.pumpTunnelPage(
      LocationPage(deviceLocator: locator, tileBuilder: testTile),
      sellerTunnelCubit: cubit,
      propertyRepository: properties,
      geoRepository: geo,
      goRouter: goRouter,
    );
    return cubit;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pump();
  }

  testWidgets('asks for the address of a new dossier', (tester) async {
    await pump(tester);
    expect(find.textContaining('Où se situe votre bien'), findsOneWidget);
    expect(find.byType(ParcelMap), findsNothing);
    expect(
      find.text(
        'Saisissez l’adresse ou géolocalisez-vous pour afficher la vue '
        'aérienne.',
      ),
      findsOneWidget,
    );
    expect(find.text('Servitude de passage'), findsOneWidget);
    expect(find.byType(ParcelCard), findsNothing);
  });

  testWidgets('shows the errors of an incomplete answer', (tester) async {
    final cubit = await pump(tester);
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    expect(find.text('Indiquez l’adresse du bien'), findsOneWidget);
    expect(find.text('Choisissez au moins une réponse.'), findsOneWidget);
    verifyNever(() => cubit.saveAndContinue(any(), any()));

    await tester.enterText(_addressInput(), 'Lieu-dit Les Pins');
    await tester.pump();
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    expect(find.text('Indiquez l’adresse du bien'), findsNothing);
    expect(find.text('Choisissez au moins une réponse.'), findsOneWidget);
  });

  testWidgets('locates an address, confirms its parcel and continues', (
    tester,
  ) async {
    final cubit = await pump(tester);
    await tester.enterText(_addressInput(), '12 rue de la Col');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('12 rue de la Colombe'), findsOneWidget);
    expect(find.text('69630 Chaponost'), findsOneWidget);

    await tester.tap(find.text('12 rue de la Colombe'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_addressInput()).controller!.text,
      testAddress.label,
    );
    expect(find.byType(ParcelMap), findsOneWidget);
    expect(find.text('Parcelle AB 98 sélectionnée'), findsOneWidget);
    expect(find.text('AB · 98'), findsOneWidget);
    expect(
      find.text(
        'J’ai localisé votre parcelle$_nbsp: section AB, n°${_nbsp}98, pour '
        '540${_nbsp}m². Cela correspond-il exactement aux limites de votre '
        'propriété$_nbsp?',
      ),
      findsOneWidget,
    );

    // Not confirmed yet.
    await tapText(tester, 'Aucune');
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    expect(
      find.text('Confirmez la parcelle ou modifiez-la avant de continuer.'),
      findsOneWidget,
    );

    await tapText(tester, 'Oui, c’est correct');
    expect(find.text('C’est confirmé'), findsOneWidget);
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();

    verify(
      () => properties.saveParcel(
        PropertyParcel(
          propertyId: 'property-id',
          idu: testParcel.idu,
          codeInsee: '69043',
          section: 'AB',
          numero: '0098',
          areaM2: 540,
          geometry: testParcel.geometry,
        ),
      ),
    ).called(1);
    verify(
      () => cubit.updateChildren(
        parcels: [
          PropertyParcel(
            id: 'new-${testParcel.idu}',
            propertyId: 'property-id',
            idu: testParcel.idu,
          ),
        ],
      ),
    ).called(1);
    final patch =
        verify(
              () => cubit.saveAndContinue(
                SellerTunnelStep.location,
                captureAny(),
              ),
            ).captured.single
            as Map<String, Object?>;
    expect(patch[PropertyColumns.addressBanId], testAddress.id);
    expect(patch[PropertyColumns.parcelConfirmed], isTrue);
    expect(patch[PropertyColumns.specialSituations], [SpecialSituation.none]);
  });

  testWidgets('allows a typed address when suggestions are unavailable', (
    tester,
  ) async {
    when(() => geo.searchAddresses(any())).thenThrow(const GeoNetworkFailure());
    await pump(tester);
    await tester.enterText(_addressInput(), '12 rue de la Col');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
      find.text(
        'Suggestions indisponibles pour le moment. Vous pouvez saisir '
        'l’adresse complète.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('selects, adds and removes parcels on the map', (tester) async {
    await pump(tester, state: _located);
    expect(find.text('Parcelle AB 98 sélectionnée'), findsOneWidget);

    await tapText(tester, 'Modifier / ajouter');
    expect(
      find.text(
        'Touchez la carte pour ajouter ou retirer une parcelle, puis '
        'confirmez.',
      ),
      findsOneWidget,
    );

    // A tap outside the selected parcel adds the one there.
    when(() => geo.parcelAt(any())).thenAnswer((_) async => eastParcel);
    final map = find.byType(ParcelMap);
    await tester.tapAt(tester.getTopLeft(map) + const Offset(20, 100));
    await tester.pump();
    expect(find.text('2 parcelles sélectionnées'), findsOneWidget);
    expect(find.text('AB · 98, AB · 99'), findsOneWidget);
    expect(
      find.textContaining('J’ai sélectionné 2 parcelles, pour 850'),
      findsOneWidget,
    );

    // A tap on a selected parcel removes it.
    await tester.tapAt(tester.getCenter(map));
    await tester.pump();
    expect(find.text('Parcelle AB 99 sélectionnée'), findsOneWidget);
  });

  testWidgets('sets the parcel buttons in 15 px text', (tester) async {
    await pump(tester, state: _located);
    final scaler = MediaQuery.textScalerOf(
      tester.element(find.text('Oui, c’est correct')),
    );
    expect(scaler.scale(16), 15);
    // Legacy API still read by some widgets.
    // ignore: deprecated_member_use
    expect(scaler.textScaleFactor, 15 / 16);
    expect(scaler.hashCode, TextScaler.noScaling.hashCode);
  });

  testWidgets('explains when no parcel is found', (tester) async {
    when(() => geo.parcelAt(any())).thenThrow(const GeoNotFoundFailure());
    await pump(tester);
    await tapText(tester, 'Me géolocaliser');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Aucune parcelle cadastrale à cet endroit. Touchez votre terrain sur '
        'la carte.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Je n’ai pas pu localiser la parcelle'),
      findsOneWidget,
    );
    expect(find.byType(ParcelCard), findsNothing);
  });

  testWidgets('lets the seller continue when the cadastre is down', (
    tester,
  ) async {
    when(() => geo.parcelAt(any())).thenThrow(const GeoNetworkFailure());
    final cubit = await pump(tester);
    await tapText(tester, 'Me géolocaliser');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Cadastre momentanément indisponible. Vous pouvez continuer$_nbsp: un '
        'expert vérifiera la parcelle.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Servitude de réseaux');
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    verify(() => cubit.saveAndContinue(SellerTunnelStep.location, any()))
        .called(1);
  });

  testWidgets('shows the lookup in progress', (tester) async {
    final parcel = Completer<CadastreParcel>();
    when(() => geo.parcelAt(any())).thenAnswer((_) => parcel.future);
    await pump(tester);
    await tapText(tester, 'Me géolocaliser');
    await tester.pump();
    expect(find.text('Recherche de la parcelle…'), findsOneWidget);
    parcel.complete(testParcel);
    await tester.pumpAndSettle();
    expect(find.text('Parcelle AB 98 sélectionnée'), findsOneWidget);
  });

  testWidgets('explains why the device position is unavailable', (
    tester,
  ) async {
    await pump(tester);
    for (final (reason, message) in [
      (
        DeviceLocationError.serviceDisabled,
        'Activez la localisation de votre téléphone pour vous géolocaliser.',
      ),
      (
        DeviceLocationError.permissionDenied,
        'Autorisez l’accès à votre position dans les réglages pour vous '
            'géolocaliser.',
      ),
      (
        DeviceLocationError.unavailable,
        'Position introuvable. Saisissez l’adresse du bien.',
      ),
    ]) {
      when(locator.currentPosition).thenThrow(DeviceLocationException(reason));
      await tapText(tester, 'Me géolocaliser');
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(LocationView)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('relocates from the map', (tester) async {
    await pump(tester, state: _located);
    await tester.tap(find.bySemanticsLabel('Me géolocaliser'));
    await tester.pumpAndSettle();
    verify(locator.currentPosition).called(1);
  });

  testWidgets('asks to describe another situation', (tester) async {
    final cubit = await pump(tester, state: _located);
    await tapText(tester, 'Oui, c’est correct');
    await tapText(tester, 'Autre');
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(RealestyTextField, 'Précisez la situation'),
        matching: find.byType(TextField),
      ),
      'Puits commun',
    );
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    final patch =
        verify(
              () => cubit.saveAndContinue(
                SellerTunnelStep.location,
                captureAny(),
              ),
            ).captured.single
            as Map<String, Object?>;
    expect(patch[PropertyColumns.specialSituationOther], 'Puits commun');
  });

  testWidgets('reports a failure to save the parcels', (tester) async {
    when(() => properties.saveParcel(any()))
        .thenThrow(const PropertySaveFailure());
    final cubit = await pump(tester);
    await tester.enterText(_addressInput(), '12 rue de la Col');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.text('12 rue de la Colombe'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Oui, c’est correct');
    await tapText(tester, 'Aucune');
    await tapText(tester, 'Continuer');
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    verifyNever(() => cubit.saveAndContinue(any(), any()));
  });

  testWidgets('disables the answers while the dossier is saved', (
    tester,
  ) async {
    await pump(
      tester,
      state: _located.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
    );
    expect(tester.widget<TextField>(_addressInput()).enabled, isFalse);
    expect(
      tester
          .widget<RealestyButton>(
            find.widgetWithText(RealestyButton, 'Oui, c’est correct'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<RealestyChoiceChip>(
            find.widgetWithText(RealestyChoiceChip, 'Aucune'),
          )
          .onSelected,
      isNull,
    );
    expect(tester.widget<ParcelMap>(find.byType(ParcelMap)).onTap, isNull);
  });

  testWidgets('disables picking a suggestion while saving', (tester) async {
    final states = StreamController<SellerTunnelState>();
    addTearDown(states.close);
    await pump(tester, states: states.stream);
    await tester.enterText(_addressInput(), '12 rue de la Col');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    states.add(
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        saveStatus: SellerTunnelSaveStatus.inProgress,
        property: testProperty,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<RealestyListItem>(find.byType(RealestyListItem).first)
          .onTap,
      isNull,
    );
  });

  testWidgets('asks to pick a suggested address', (tester) async {
    await pump(tester);
    await tester.enterText(_addressInput(), '12 rue de la Colombe');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    expect(find.text('Choisissez une adresse dans la liste'), findsOneWidget);
  });

  testWidgets('asks for a parcel when all were removed', (tester) async {
    await pump(tester, state: _located);
    await tapText(tester, 'Modifier / ajouter');
    await tester.tapAt(tester.getCenter(find.byType(ParcelMap)));
    await tester.pump();
    await tapText(tester, 'Aucune');
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    expect(
      find.text('Sélectionnez au moins une parcelle sur la carte.'),
      findsOneWidget,
    );
  });

  testWidgets('asks for the special situations last', (tester) async {
    when(() => geo.parcelAt(any())).thenThrow(const GeoNetworkFailure());
    await pump(tester);
    await tapText(tester, 'Me géolocaliser');
    await tester.pumpAndSettle();
    await tapText(tester, 'Continuer');
    await tester.pumpAndSettle();
    expect(find.text('Choisissez au moins une réponse.'), findsOneWidget);
    expect(find.text('Choisissez une adresse dans la liste'), findsNothing);
  });

  Finder button(String label) => find.widgetWithText(RealestyButton, label);

  testWidgets('stacks the parcel buttons when they do not fit', (tester) async {
    await pump(tester, state: _located, textScale: 1.3);
    final confirm = tester.getRect(button('Oui, c’est correct'));
    final edit = tester.getRect(button('Modifier / ajouter'));
    expect(edit.top, greaterThan(confirm.bottom));
    expect(
      tester.widget<RealestyButton>(button('Oui, c’est correct')).leadingIcon,
      RealestyIcons.check,
    );
  });

  testWidgets('sets the parcel buttons side by side when they fit', (
    tester,
  ) async {
    await pump(tester, state: _located, width: 600);
    final confirm = tester.getRect(button('Oui, c’est correct'));
    final edit = tester.getRect(button('Modifier / ajouter'));
    expect(edit.top, confirm.top);
    expect(edit.left, greaterThan(confirm.right));
  });

  testWidgets('goes back to the owners step', (tester) async {
    final goRouter = MockGoRouter();
    await pump(tester, goRouter: goRouter);
    await tester.tap(find.bySemanticsLabel('Retour'));
    verify(() => goRouter.go(AppRoutes.sellerOwners)).called(1);
  });
}
