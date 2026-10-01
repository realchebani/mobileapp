import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:mobileapp/seller_tunnel/steps/location/cubit/location_cubit.dart';
import 'package:property_repository/property_repository.dart';

import '../location_fixtures.dart';

void main() {
  const property = Property(
    id: 'property-id',
    ownerId: 'user-id',
    provenance: {'purchase_year': 'document'},
  );

  group('LocationState', () {
    test('toPatch saves a BAN address as external data', () {
      final state = LocationState(
        addressText: ' ${testAddress.label} ',
        address: testAddress,
        point: testPoint,
        parcels: [testParcel],
        parcelConfirmed: true,
        situations: const [SpecialSituation.rightOfWay],
        otherSituation: 'ignored',
      );
      expect(state.toPatch(property), {
        'address_label': testAddress.label,
        'address_housenumber': '12',
        'address_street': 'rue de la Colombe',
        'address_postcode': '69630',
        'address_city': 'Chaponost',
        'address_citycode': '69043',
        'address_ban_id': '69043_jj2dze_00012',
        'lat': 45.707956,
        'lng': 4.739579,
        'parcel_confirmed': true,
        'special_situations': const [SpecialSituation.rightOfWay],
        'special_situation_other': null,
        'provenance': {
          'purchase_year': 'document',
          for (final column in [
            'address_label',
            'address_housenumber',
            'address_street',
            'address_postcode',
            'address_city',
            'address_citycode',
            'address_ban_id',
            'lat',
            'lng',
          ])
            column: 'external',
        },
      });
    });

    test('toPatch saves a typed address as declared', () {
      const state = LocationState(
        addressText: 'Lieu-dit Les Pins',
        parcelConfirmed: true,
        situations: [SpecialSituation.other],
        otherSituation: ' Puits commun ',
      );
      final patch = state.toPatch(property);
      expect(patch['address_ban_id'], isNull);
      expect(patch['lat'], isNull);
      expect(patch['parcel_confirmed'], isFalse);
      expect(patch['special_situation_other'], 'Puits commun');
      expect((patch['provenance']! as Map)['address_label'], 'declared');
      expect(
        const LocationState(
          situations: [SpecialSituation.other],
          otherSituation: ' ',
        ).toPatch(property)['special_situation_other'],
        isNull,
      );
    });

    test('mapCenter is the point, else the middle of the first parcel', () {
      expect(const LocationState().mapCenter, isNull);
      expect(const LocationState(point: testPoint).mapCenter, testPoint);
      final center = LocationState(
        parcels: [
          const CadastreParcel(idu: 'none'),
          testParcel,
        ],
      ).mapCenter!;
      // The closing vertex counts twice: close to, not exactly, the center.
      expect(center.lat, closeTo(testPoint.lat, 1e-4));
      expect(center.lng, closeTo(testPoint.lng, 1e-4));
    });

    test('totalAreaM2 adds the known areas', () {
      expect(
        LocationState(
          parcels: [testParcel, eastParcel, squareParcel(areaM2: null)],
        ).totalAreaM2,
        850,
      );
    });

    test('requires a picked or located address unless offline', () {
      const typed = LocationState(addressText: '12 rue');
      expect(typed.addressNotPicked, isTrue);
      expect(typed.servicesUnavailable, isFalse);
      expect(
        const LocationState(
          addressText: '12 rue',
          point: testPoint,
        ).addressNotPicked,
        isFalse,
      );
      expect(
        const LocationState(
          addressText: '12 rue',
          suggestionsUnavailable: true,
        ).addressNotPicked,
        isFalse,
      );
      expect(
        const LocationState(
          addressText: '12 rue',
          parcelStatus: ParcelLookupStatus.failure,
        ).addressNotPicked,
        isFalse,
      );
      expect(const LocationState().addressNotPicked, isFalse);
    });

    test('requires a parcel while the cadastre answers', () {
      expect(
        const LocationState(parcelStatus: ParcelLookupStatus.success)
            .parcelsMissing,
        isTrue,
      );
      expect(
        const LocationState(parcelStatus: ParcelLookupStatus.notFound)
            .parcelsMissing,
        isFalse,
      );
      expect(
        LocationState(
          parcelStatus: ParcelLookupStatus.success,
          parcels: [testParcel],
        ).parcelsMissing,
        isFalse,
      );
    });

    test('is valid once answered', () {
      const empty = LocationState();
      expect(empty.isValid, isFalse);
      expect(empty.addressMissing, isTrue);
      expect(empty.situationsMissing, isTrue);
      expect(empty.isSubmitting, isFalse);
      final unconfirmed = LocationState(
        addressText: 'a',
        address: testAddress,
        parcels: [testParcel],
        situations: const [SpecialSituation.none],
      );
      expect(unconfirmed.confirmationMissing, isTrue);
      expect(unconfirmed.isValid, isFalse);
      expect(unconfirmed.copyWith(parcelConfirmed: true).isValid, isTrue);
      expect(
        const LocationState(submitStatus: LocationSubmitStatus.inProgress)
            .isSubmitting,
        isTrue,
      );
    });
  });
}
