import 'package:property_repository/property_repository.dart';
import 'package:test/test.dart';

void main() {
  group(MarketSnapshot, () {
    test('parses a full row', () {
      final snapshot = MarketSnapshot.fromJson(const {
        'id': 's1',
        'property_id': 'p1',
        'status': 'ok',
        'reason': null,
        'created_at': '2026-10-01T10:00:00Z',
        'computed_at': '2026-10-01T10:00:05Z',
        'data_until': '2025-12-19',
        'property_type': 'maison',
        'living_area_m2': 115.0,
        'city': 'Chaponost',
        'estimate_low_eur': 420000,
        'estimate_median_eur': 479000,
        'estimate_high_eur': 546000,
        'price_m2_low': 3572,
        'price_m2_median': 4162,
        'price_m2_high': 4648,
        'confidence': 79,
        'comparables_count': 27,
        'scope': 'radius',
        'radius_m': 500,
        'months': 36,
        'sales_12m': 62,
        'yoy_change_pct': 0.2,
        'semester_medians': [
          {'semester': '2025-S2', 'median_m2': 4344, 'count': 38},
          'ignored',
        ],
        'comparables': [
          {
            'type': 'maison',
            'street': 'Rue des Platanes',
            'area_m2': 96,
            'rooms': 4,
            'land_m2': 286,
            'sold_on': '2025-10',
            'distance_m': 350,
            'price_eur': 384900,
            'price_m2_eur': 4009,
          },
        ],
        'factors': [
          {'sign': '+', 'label': 'Piscine'},
          {'sign': '-', 'label': 'Route'},
        ],
        'explanation_fr': 'Texte',
      });
      expect(snapshot.status, MarketSnapshotStatus.ok);
      expect(snapshot.isFinal, isTrue);
      expect(snapshot.dataUntil, DateTime(2025, 12, 19));
      expect(snapshot.propertyType, PropertyType.house);
      expect(snapshot.scope, MarketScope.radius);
      expect(snapshot.confidenceLevel, EstimateConfidenceLevel.high);
      expect(snapshot.yoyChangePct, 0.2);
      expect(snapshot.semesterMedians, const [
        SemesterMedian(semester: '2025-S2', medianM2: 4344, count: 38),
      ]);
      expect(
        snapshot.comparables.single,
        ComparableSale(
          propertyType: PropertyType.house,
          street: 'Rue des Platanes',
          areaM2: 96,
          rooms: 4,
          landM2: 286,
          soldOn: DateTime(2025, 10),
          distanceM: 350,
          priceEur: 384900,
          priceM2Eur: 4009,
        ),
      );
      expect(snapshot.factors, const [
        MarketFactor(positive: true, label: 'Piscine'),
        MarketFactor(positive: false, label: 'Route'),
      ]);
      expect(snapshot.explanation, 'Texte');
      expect(snapshot.props, isNotEmpty);
    });

    test('parses a minimal row', () {
      final snapshot = MarketSnapshot.fromJson(const {
        'id': 's1',
        'property_id': 'p1',
        'status': 'weird',
        'created_at': '2026-10-01T10:00:00Z',
        'comparables': [
          {'sold_on': null},
        ],
        'factors': [<String, dynamic>{}],
        'semester_medians': [<String, dynamic>{}],
      });
      expect(snapshot.status, MarketSnapshotStatus.error);
      expect(snapshot.isFinal, isFalse);
      expect(snapshot.confidenceLevel, isNull);
      expect(snapshot.comparables.single.soldOn, DateTime(1970));
      expect(snapshot.comparables.single.areaM2, 0);
      expect(snapshot.factors.single.label, '');
      expect(snapshot.semesterMedians.single.semester, '');
    });

    test('insufficient is final', () {
      final snapshot = MarketSnapshot(
        id: 's',
        propertyId: 'p',
        status: MarketSnapshotStatus.insufficient,
        createdAt: DateTime(2026),
      );
      expect(snapshot.isFinal, isTrue);
    });
  });

  test('EstimateConfidenceLevel.of', () {
    expect(EstimateConfidenceLevel.of(70), EstimateConfidenceLevel.high);
    expect(EstimateConfidenceLevel.of(40), EstimateConfidenceLevel.medium);
    expect(EstimateConfidenceLevel.of(39), EstimateConfidenceLevel.low);
  });
}
