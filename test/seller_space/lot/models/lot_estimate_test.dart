import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/lot/models/lot_estimate.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  Property property(
    String id,
    PropertyType? type, {
    int? low,
    int? median,
    int? high,
  }) => Property(
    id: id,
    ownerId: 'u',
    propertyType: type,
    aiEstimateLowEur: low,
    aiEstimateMedianEur: median,
    aiEstimateHighEur: high,
  );

  final house = property(
    'house',
    PropertyType.house,
    low: 300000,
    median: 320000,
    high: 340000,
  );
  final garage = property(
    'garage',
    PropertyType.parking,
    low: 15000,
    median: 18000,
    high: 21000,
  );

  group(LotEstimate, () {
    test('adds the estimates of the properties', () {
      final estimate = LotEstimate.of(
        members: [house, garage, property('land', PropertyType.land)],
        parcels: const {},
      );
      expect(estimate.isComplete, isTrue);
      expect(
        (estimate.low, estimate.median, estimate.high),
        (315000, 338000, 361000),
      );
      expect(estimate.members, {
        'house': LotMemberEstimate.included,
        'garage': LotMemberEstimate.included,
        'land': LotMemberEstimate.byExpert,
      });
    });

    test('never adds an outbuilding on a parcel of the main dwelling', () {
      final estimate = LotEstimate.of(
        members: [garage, house],
        parcels: const {
          'house': {'P1', 'P2'},
          'garage': {'P2'},
        },
      );
      expect(estimate.members['garage'], LotMemberEstimate.includedInMain);
      expect(estimate.median, 320000);
      // The main property chosen by the seller.
      final chosen = LotEstimate.of(
        members: [garage, house],
        parcels: const {
          'house': {'P1'},
          'garage': {'P1'},
        },
        mainPropertyId: 'garage',
      );
      expect(chosen.members['garage'], LotMemberEstimate.included);
    });

    test('waits for every property that can be estimated', () {
      final estimate = LotEstimate.of(
        members: [house, property('garage', PropertyType.parking)],
        parcels: const {},
      );
      expect(estimate.isComplete, isFalse);
      expect(estimate.members['garage'], LotMemberEstimate.waiting);
      expect(
        LotEstimate.of(
          members: [property('land', PropertyType.land)],
          parcels: const {},
        ).isComplete,
        isFalse,
      );
    });

    test('a lot without dwelling has no main dwelling', () {
      final estimate = LotEstimate.of(
        members: [garage, property('cellar', PropertyType.outbuilding)],
        parcels: const {
          'garage': {'P1'},
          'cellar': {'P1'},
        },
      );
      expect(estimate.members['cellar'], LotMemberEstimate.waiting);
      expect(
        LotEstimate.of(
          members: [property('land', PropertyType.land), garage],
          parcels: const {},
          mainPropertyId: 'land',
        ).members['garage'],
        LotMemberEstimate.included,
      );
    });

    test('adds a dwelling on the parcel of another one', () {
      final apartment = property(
        'apartment',
        PropertyType.apartment,
        low: 100000,
        median: 110000,
        high: 120000,
      );
      final estimate = LotEstimate.of(
        members: [house, apartment],
        parcels: const {
          'house': {'P1'},
          'apartment': {'P1'},
        },
      );
      expect(estimate.members['apartment'], LotMemberEstimate.included);
      expect(estimate.median, 430000);
      expect(
        estimate,
        LotEstimate.of(members: [house, apartment], parcels: const {}),
      );
    });
  });
}
