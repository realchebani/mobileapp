import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:mobileapp/seller_tunnel/steps/location/cubit/location_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/location/data/device_locator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';
import '../location_fixtures.dart';

class _MockDeviceLocator extends Mock implements DeviceLocator;

void main() {
  const property = Property(id: 'property-id', ownerId: 'user-id');
  const savedRow = PropertyParcel(
    id: 'row-98',
    propertyId: 'property-id',
    idu: '69043000AB0098',
  );

  late GeoRepository geo;
  late PropertyRepository properties;
  late DeviceLocator locator;

  setUpAll(() {
    registerFallbackValue(testPoint);
    registerFallbackValue(savedRow);
  });

  setUp(() {
    geo = MockGeoRepository();
    properties = MockPropertyRepository();
    locator = _MockDeviceLocator();
    when(() => geo.parcelAt(any())).thenAnswer((_) async => testParcel);
  });

  LocationCubit build({
    Property dossier = property,
    List<PropertyParcel> parcels = const [],
  }) => LocationCubit(
    geoRepository: geo,
    propertyRepository: properties,
    deviceLocator: locator,
    property: dossier,
    parcels: parcels,
    searchDebounce: Duration.zero,
  );

  /// A state with [testParcel] selected around [testAddress].
  LocationState located({
    List<CadastreParcel>? parcels,
    bool confirmed = false,
    bool editing = false,
  }) => LocationState(
    addressText: testAddress.label,
    address: testAddress,
    point: testPoint,
    parcelStatus: ParcelLookupStatus.success,
    parcels: parcels ?? [testParcel],
    parcelConfirmed: confirmed,
    isEditingParcels: editing,
  );

  group('initial state', () {
    test('is empty for a new dossier', () {
      expect(build().state, const LocationState());
    });

    test('restores the saved answers', () {
      final cubit = build(
        dossier: const Property(
          id: 'property-id',
          ownerId: 'user-id',
          addressLabel: '12 rue de la Colombe 69630 Chaponost',
          addressHousenumber: '12',
          addressStreet: 'rue de la Colombe',
          addressPostcode: '69630',
          addressCity: 'Chaponost',
          addressCitycode: '69043',
          addressBanId: '69043_jj2dze_00012',
          lat: 45.707956,
          lng: 4.739579,
          parcelConfirmed: true,
          specialSituations: [SpecialSituation.other],
          specialSituationOther: 'Puits commun',
        ),
        parcels: [
          PropertyParcel(
            id: 'row-98',
            propertyId: 'property-id',
            idu: testParcel.idu,
            codeInsee: '69043',
            section: 'AB',
            numero: '0098',
            areaM2: 540,
            geometry: testParcel.geometry,
          ),
        ],
      );
      final state = cubit.state;
      expect(state.address, testAddress.copyWithoutType());
      expect(state.point, testPoint);
      expect(state.parcels.single.idu, testParcel.idu);
      expect(state.parcels.single.outlines, testParcel.outlines);
      expect(state.parcelStatus, ParcelLookupStatus.success);
      expect(state.parcelConfirmed, isTrue);
      expect(state.situations, [SpecialSituation.other]);
      expect(state.otherSituation, 'Puits commun');
      expect(state.savedParcels, hasLength(1));
    });

    test('keeps a typed address without BAN identifier', () {
      final state = build(
        dossier: const Property(
          id: 'property-id',
          ownerId: 'user-id',
          addressLabel: 'Lieu-dit Les Pins',
          parcelConfirmed: true,
        ),
      ).state;
      expect(state.addressText, 'Lieu-dit Les Pins');
      expect(state.address, isNull);
      expect(state.point, isNull);
      expect(state.parcelConfirmed, isFalse);
    });
  });

  group('addressChanged', () {
    blocTest<LocationCubit, LocationState>(
      'searches the BAN after the debounce',
      setUp: () =>
          when(() => geo.searchAddresses(any()))
              .thenAnswer((_) async => [testAddress]),
      build: build,
      act: (cubit) => cubit.addressChanged('12 rue de la Col'),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const LocationState(addressText: '12 rue de la Col'),
        const LocationState(
          addressText: '12 rue de la Col',
          suggestions: [testAddress],
        ),
      ],
      verify: (_) => verify(() => geo.searchAddresses('12 rue de la Col')),
    );

    blocTest<LocationCubit, LocationState>(
      'clears the suggestions and the BAN address of a short text',
      build: build,
      seed: () => located().copyWith(suggestions: [testAddress]),
      act: (cubit) => cubit.addressChanged('12'),
      wait: const Duration(milliseconds: 10),
      expect: () => [const LocationState(addressText: '12')],
      verify: (_) => verifyNever(() => geo.searchAddresses(any())),
    );

    blocTest<LocationCubit, LocationState>(
      'forgets the position and parcels of a picked address being edited',
      setUp: () =>
          when(() => geo.searchAddresses(any()))
              .thenAnswer((_) async => const []),
      build: build,
      seed: () =>
          located(confirmed: true)
              .copyWith(parcelStatus: ParcelLookupStatus.failure),
      act: (cubit) => cubit.addressChanged('12 rue de la Colombe, Lyon'),
      wait: const Duration(milliseconds: 10),
      expect: () => const [
        LocationState(
          addressText: '12 rue de la Colombe, Lyon',
          parcelStatus: ParcelLookupStatus.failure,
        ),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'ignores an unchanged text',
      build: build,
      act: (cubit) => cubit.addressChanged(''),
      expect: () => const <LocationState>[],
    );

    blocTest<LocationCubit, LocationState>(
      'reports unavailable suggestions (offline)',
      setUp: () =>
          when(() => geo.searchAddresses(any()))
              .thenThrow(const GeoNetworkFailure()),
      build: build,
      act: (cubit) => cubit.addressChanged('12 rue'),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const LocationState(addressText: '12 rue'),
        const LocationState(
          addressText: '12 rue',
          suggestionsUnavailable: true,
        ),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'drops the results of an outdated search',
      setUp: () {
        final first = Completer<List<GeoAddress>>();
        when(() => geo.searchAddresses('12 rue')).thenAnswer((_) {
          return first.future;
        });
        when(() => geo.searchAddresses('12 rue de')).thenAnswer((_) async {
          first.complete([testAddress]);
          return const [];
        });
      },
      build: build,
      act: (cubit) async {
        cubit.addressChanged('12 rue');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        cubit.addressChanged('12 rue de');
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const LocationState(addressText: '12 rue'),
        const LocationState(addressText: '12 rue de'),
      ],
    );

    test('ignores results arriving after close', () async {
      final results = Completer<List<GeoAddress>>();
      when(() => geo.searchAddresses(any())).thenAnswer((_) => results.future);
      final cubit = build()..addressChanged('12 rue');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.close();
      results.complete([testAddress]);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.suggestions, isEmpty);
    });
  });

  group('suggestionSelected', () {
    blocTest<LocationCubit, LocationState>(
      'locates the address and its parcel',
      build: build,
      seed: () => const LocationState(
        addressText: '12 rue',
        suggestions: [testAddress],
      ),
      act: (cubit) => cubit.suggestionSelected(testAddress),
      expect: () => [
        LocationState(
          addressText: testAddress.label,
          address: testAddress,
          point: testPoint,
        ),
        LocationState(
          addressText: testAddress.label,
          address: testAddress,
          point: testPoint,
          parcelStatus: ParcelLookupStatus.loading,
        ),
        located(),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'clears the previous parcels when there is none at the address',
      setUp: () =>
          when(() => geo.parcelAt(any())).thenThrow(const GeoNotFoundFailure()),
      build: build,
      seed: () => located(parcels: [eastParcel], confirmed: true),
      act: (cubit) => cubit.suggestionSelected(testAddress),
      skip: 1,
      expect: () => [
        located(parcels: const [])
            .copyWith(parcelStatus: ParcelLookupStatus.notFound),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'reports an unavailable cadastre',
      setUp: () =>
          when(() => geo.parcelAt(any())).thenThrow(const GeoNetworkFailure()),
      build: build,
      act: (cubit) => cubit.suggestionSelected(testAddress),
      skip: 2,
      expect: () => [
        located(parcels: const [])
            .copyWith(parcelStatus: ParcelLookupStatus.failure),
      ],
    );

    test('ignores a lookup answered after close', () async {
      final parcel = Completer<CadastreParcel>();
      when(() => geo.parcelAt(any())).thenAnswer((_) => parcel.future);
      final cubit = build();
      final selection = cubit.suggestionSelected(testAddress);
      await cubit.close();
      parcel.complete(testParcel);
      await selection;
      expect(cubit.state.parcels, isEmpty);
    });

    test('ignores an outdated lookup', () async {
      final slow = Completer<CadastreParcel>();
      when(() => geo.parcelAt(testPoint)).thenAnswer((_) => slow.future);
      const other = GeoPoint(45.8, 4.8);
      when(() => geo.parcelAt(other)).thenAnswer((_) async => eastParcel);
      final cubit = build();
      final first = cubit.suggestionSelected(testAddress);
      await cubit.mapTapped(other);
      slow.complete(testParcel);
      await first;
      expect(cubit.state.parcels, [eastParcel]);
      await cubit.close();
    });
  });

  group('locate', () {
    setUp(() {
      when(locator.currentPosition).thenAnswer((_) async => testPoint);
      when(() => geo.reverseGeocode(any()))
          .thenAnswer((_) async => testAddress);
    });

    blocTest<LocationCubit, LocationState>(
      'fills the address and the parcel of the device position',
      build: build,
      act: (cubit) => cubit.locate(),
      expect: () => [
        const LocationState(isLocating: true),
        LocationState(
          addressText: testAddress.label,
          address: testAddress,
          point: testPoint,
        ),
        LocationState(
          addressText: testAddress.label,
          address: testAddress,
          point: testPoint,
          parcelStatus: ParcelLookupStatus.loading,
        ),
        located(),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'keeps the typed address when reverse geocoding fails',
      setUp: () =>
          when(() => geo.reverseGeocode(any()))
              .thenThrow(const GeoNetworkFailure()),
      build: build,
      seed: () => const LocationState(addressText: 'Chez moi'),
      act: (cubit) => cubit.locate(),
      skip: 1,
      expect: () => [
        const LocationState(addressText: 'Chez moi', point: testPoint),
        const LocationState(
          addressText: 'Chez moi',
          point: testPoint,
          parcelStatus: ParcelLookupStatus.loading,
        ),
        LocationState(
          addressText: 'Chez moi',
          point: testPoint,
          parcelStatus: ParcelLookupStatus.success,
          parcels: [testParcel],
        ),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'reports why the position is unavailable',
      setUp: () => when(locator.currentPosition).thenThrow(
        const DeviceLocationException(DeviceLocationError.permissionDenied),
      ),
      build: build,
      seed: () =>
          const LocationState(locateError: DeviceLocationError.unavailable),
      act: (cubit) => cubit.locate(),
      expect: () => [
        const LocationState(isLocating: true),
        const LocationState(locateError: DeviceLocationError.permissionDenied),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'does nothing while locating',
      build: build,
      seed: () => const LocationState(isLocating: true),
      act: (cubit) => cubit.locate(),
      expect: () => const <LocationState>[],
    );

    test('stops when closed while getting the position', () async {
      final position = Completer<GeoPoint>();
      when(locator.currentPosition).thenAnswer((_) => position.future);
      final cubit = build();
      final locating = cubit.locate();
      await cubit.close();
      position.complete(testPoint);
      await locating;
      expect(cubit.state.point, isNull);
    });

    test('stops when closed while failing', () async {
      final position = Completer<GeoPoint>();
      when(locator.currentPosition).thenAnswer((_) => position.future);
      final cubit = build();
      final locating = cubit.locate();
      await cubit.close();
      position.completeError(
        const DeviceLocationException(DeviceLocationError.unavailable),
      );
      await locating;
      expect(cubit.state.locateError, isNull);
    });
  });

  group('mapTapped', () {
    const outside = GeoPoint(45.7, 4.7);

    blocTest<LocationCubit, LocationState>(
      'selects the parcel tapped instead of the current one',
      setUp: () =>
          when(() => geo.parcelAt(outside)).thenAnswer((_) async => eastParcel),
      build: build,
      seed: () => located(confirmed: true),
      act: (cubit) => cubit.mapTapped(outside),
      expect: () => [
        located(confirmed: true)
            .copyWith(parcelStatus: ParcelLookupStatus.loading),
        located(parcels: [eastParcel]),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'keeps the selection when there is no parcel there',
      setUp: () =>
          when(() => geo.parcelAt(outside))
              .thenThrow(const GeoNotFoundFailure()),
      build: build,
      seed: () => located(confirmed: true),
      act: (cubit) => cubit.mapTapped(outside),
      skip: 1,
      expect: () => [
        located(confirmed: true)
            .copyWith(parcelStatus: ParcelLookupStatus.notFound),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'ignores a tap on the selected parcel',
      build: build,
      seed: located,
      act: (cubit) => cubit.mapTapped(testPoint),
      expect: () => const <LocationState>[],
    );

    blocTest<LocationCubit, LocationState>(
      'removes a selected parcel tapped while editing',
      build: build,
      seed: () => located(parcels: [testParcel, eastParcel], editing: true),
      act: (cubit) => cubit.mapTapped(testPoint),
      expect: () => [
        located(parcels: [eastParcel], editing: true),
      ],
      verify: (_) => verifyNever(() => geo.parcelAt(any())),
    );

    blocTest<LocationCubit, LocationState>(
      'adds the parcel tapped while editing',
      setUp: () =>
          when(() => geo.parcelAt(outside)).thenAnswer((_) async => eastParcel),
      build: build,
      seed: () => located(editing: true),
      act: (cubit) => cubit.mapTapped(outside),
      skip: 1,
      expect: () => [
        located(parcels: [testParcel, eastParcel], editing: true),
      ],
    );

    blocTest<LocationCubit, LocationState>(
      'removes a selected parcel found by the cadastre while editing',
      setUp: () =>
          when(() => geo.parcelAt(outside)).thenAnswer((_) async => eastParcel),
      build: build,
      seed: () => located(
        parcels: [
          testParcel,
          squareParcel(idu: eastParcel.idu, half: 0),
        ],
        editing: true,
      ),
      act: (cubit) => cubit.mapTapped(outside),
      skip: 1,
      expect: () => [located(editing: true)],
    );
  });

  group('fast taps while editing', () {
    const a = GeoPoint(45.7, 4.7);
    const b = GeoPoint(45.6, 4.6);

    test('applies every answer, in any order', () async {
      final first = Completer<CadastreParcel>();
      final second = Completer<CadastreParcel>();
      when(() => geo.parcelAt(a)).thenAnswer((_) => first.future);
      when(() => geo.parcelAt(b)).thenAnswer((_) => second.future);
      final cubit = _seeded(build(), located(editing: true));
      final tapA = cubit.mapTapped(a);
      final tapB = cubit.mapTapped(b);
      second.complete(eastParcel);
      await tapB;
      // The first tap is still pending.
      expect(cubit.state.parcelStatus, ParcelLookupStatus.loading);
      expect(cubit.state.parcels, [testParcel, eastParcel]);
      // Removing a parcel meanwhile keeps the lookup visible.
      await cubit.mapTapped(testPoint);
      expect(cubit.state.parcelStatus, ParcelLookupStatus.loading);
      first.complete(squareParcel(idu: 'third', center: a));
      await tapA;
      expect(cubit.state.parcelStatus, ParcelLookupStatus.success);
      expect(cubit.state.parcels.map((p) => p.idu), [eastParcel.idu, 'third']);
      await cubit.close();
    });

    test('drops the taps answered after a new address', () async {
      final pending = Completer<CadastreParcel>();
      when(() => geo.parcelAt(a)).thenAnswer((_) => pending.future);
      final cubit = _seeded(build(), located(editing: true));
      final tap = cubit.mapTapped(a);
      await cubit.suggestionSelected(testAddress);
      pending.complete(eastParcel);
      await tap;
      expect(cubit.state.parcels, [testParcel]);
      await cubit.close();
    });
  });

  group('confirmation', () {
    blocTest<LocationCubit, LocationState>(
      'confirmParcels confirms and stops editing',
      build: build,
      seed: () => located(editing: true),
      act: (cubit) => cubit.confirmParcels(),
      expect: () => [located(confirmed: true)],
    );

    blocTest<LocationCubit, LocationState>(
      'editParcels starts editing and withdraws the confirmation',
      build: build,
      seed: () => located(confirmed: true),
      act: (cubit) => cubit.editParcels(),
      expect: () => [located(editing: true)],
    );
  });

  group('special situations', () {
    blocTest<LocationCubit, LocationState>(
      '"Aucune" excludes the others and the others exclude it',
      build: build,
      act: (cubit) => cubit
        ..situationToggled(SpecialSituation.other, selected: true)
        ..situationToggled(SpecialSituation.rightOfWay, selected: true)
        ..situationToggled(SpecialSituation.none, selected: true)
        ..situationToggled(SpecialSituation.networkEasement, selected: true)
        ..situationToggled(SpecialSituation.networkEasement, selected: false)
        ..otherSituationChanged('Puits'),
      expect: () => const [
        LocationState(situations: [SpecialSituation.other]),
        LocationState(
          situations: [SpecialSituation.rightOfWay, SpecialSituation.other],
        ),
        LocationState(situations: [SpecialSituation.none]),
        LocationState(situations: [SpecialSituation.networkEasement]),
        LocationState(),
        LocationState(otherSituation: 'Puits'),
      ],
    );
  });

  group('submit', () {
    final complete = located(confirmed: true)
        .copyWith(situations: [SpecialSituation.none], showErrors: true);

    blocTest<LocationCubit, LocationState>(
      'shows the errors of incomplete answers',
      build: build,
      act: (cubit) => cubit.submit(),
      expect: () => const [LocationState(showErrors: true, submitAttempts: 1)],
    );

    blocTest<LocationCubit, LocationState>(
      'does nothing while submitting',
      build: build,
      seed: () =>
          complete.copyWith(submitStatus: LocationSubmitStatus.inProgress),
      act: (cubit) => cubit.submit(),
      expect: () => const <LocationState>[],
    );

    const old = PropertyParcel(
      id: 'row-old',
      propertyId: 'property-id',
      idu: 'old',
    );
    const unsaved = PropertyParcel(propertyId: 'property-id', idu: 'x');
    const saved98 = PropertyParcel(
      id: 'new-98',
      propertyId: 'property-id',
      idu: '69043000AB0098',
    );

    blocTest<LocationCubit, LocationState>(
      'replaces the unselected parcel rows by the selected ones',
      setUp: () {
        when(() => properties.deleteParcel(any())).thenAnswer((_) async {});
        when(() => properties.saveParcel(any()))
            .thenAnswer((_) async => saved98);
      },
      build: build,
      seed: () => complete.copyWith(savedParcels: const [old, unsaved]),
      act: (cubit) => cubit.submit(),
      expect: () => [
        complete.copyWith(
          savedParcels: const [old, unsaved],
          submitStatus: LocationSubmitStatus.inProgress,
        ),
        complete.copyWith(
          savedParcels: const [saved98],
          submitStatus: LocationSubmitStatus.success,
        ),
      ],
      verify: (_) {
        verify(() => properties.deleteParcel('row-old')).called(1);
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
      },
    );

    blocTest<LocationCubit, LocationState>(
      'keeps the rows written before a failure, to retry without duplicates',
      setUp: () {
        when(() => properties.deleteParcel(any())).thenAnswer((_) async {});
        when(() => properties.saveParcel(any()))
            .thenThrow(const PropertySaveFailure());
      },
      build: build,
      seed: () => complete
          .copyWith(savedParcels: const [savedRow])
          .copyWith(parcels: [eastParcel]),
      act: (cubit) => cubit.submit(),
      expect: () => [
        complete
            .copyWith(savedParcels: const [savedRow], parcels: [eastParcel])
            .copyWith(submitStatus: LocationSubmitStatus.inProgress),
        complete.copyWith(
          parcels: [eastParcel],
          submitStatus: LocationSubmitStatus.failure,
          savedParcels: const [],
        ),
      ],
      errors: () => [isA<PropertySaveFailure>()],
    );

    blocTest<LocationCubit, LocationState>(
      'succeeds without writes when the rows are up to date',
      build: build,
      seed: () => complete.copyWith(savedParcels: const [savedRow]),
      act: (cubit) => cubit.submit(),
      skip: 1,
      expect: () => [
        complete.copyWith(
          savedParcels: const [savedRow],
          submitStatus: LocationSubmitStatus.success,
        ),
      ],
      verify: (_) => verifyNever(() => properties.saveParcel(any())),
    );

    test('fails when a parcel write does not answer', () async {
      when(() => properties.saveParcel(any()))
          .thenAnswer((_) => Completer<PropertyParcel>().future);
      final cubit = _seeded(
        LocationCubit(
          geoRepository: geo,
          propertyRepository: properties,
          deviceLocator: locator,
          property: property,
          parcels: const [],
          writeTimeout: const Duration(milliseconds: 10),
        ),
        complete,
      );
      await cubit.submit();
      expect(cubit.state.submitStatus, LocationSubmitStatus.failure);
      await cubit.close();
    });

    test('stops when closed while saving', () async {
      final save = Completer<PropertyParcel>();
      when(() => properties.saveParcel(any())).thenAnswer((_) => save.future);
      final cubit = _seeded(build(), complete);
      final submitting = cubit.submit();
      await cubit.close();
      save.complete(savedRow);
      await submitting;
      expect(cubit.state.submitStatus, LocationSubmitStatus.inProgress);
    });

    test('stops when closed while failing', () async {
      final save = Completer<PropertyParcel>();
      when(() => properties.saveParcel(any())).thenAnswer((_) => save.future);
      final cubit = _seeded(build(), complete);
      final submitting = cubit.submit();
      await cubit.close();
      save.completeError(const PropertySaveFailure());
      await submitting;
      expect(cubit.state.submitStatus, LocationSubmitStatus.inProgress);
    });
  });
}

extension on GeoAddress {
  /// The address as restored from the dossier (no BAN type nor name).
  GeoAddress copyWithoutType() => GeoAddress(
    id: id,
    label: label,
    point: point,
    housenumber: housenumber,
    street: street,
    postcode: postcode,
    city: city,
    citycode: citycode,
  );
}

/// [cubit] in [state] (as `blocTest` seeds do).
LocationCubit _seeded(LocationCubit cubit, LocationState state) =>
    cubit..emit(state);
