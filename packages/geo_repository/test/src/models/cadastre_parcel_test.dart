import 'package:geo_repository/geo_repository.dart';
import 'package:test/test.dart';

void main() {
  const square = [
    [0.0, 0.0],
    [1.0, 0.0],
    [1.0, 1.0],
    [0.0, 0.0],
  ];

  group('CadastreParcel', () {
    test('is built from an API Carto feature', () {
      final parcel = CadastreParcel.fromFeature(const {
        'geometry': {
          'type': 'MultiPolygon',
          'coordinates': [
            [square],
          ],
        },
        'properties': {
          'numero': '0076',
          'section': 'AM',
          'nom_com': 'Chaponost',
          'idu': '69043000AM0076',
          'contenance': 947,
          'code_insee': '69043',
        },
      });
      expect(
        parcel,
        const CadastreParcel(
          idu: '69043000AM0076',
          section: 'AM',
          numero: '0076',
          codeInsee: '69043',
          communeName: 'Chaponost',
          areaM2: 947,
          geometry: {
            'type': 'MultiPolygon',
            'coordinates': [
              [square],
            ],
          },
        ),
      );
    });

    test('shortNumero drops the leading zeros', () {
      expect(const CadastreParcel(idu: 'i', numero: '0076').shortNumero, '76');
      expect(
        const CadastreParcel(idu: 'i', numero: '0000').shortNumero,
        '0000',
      );
      expect(const CadastreParcel(idu: 'i', numero: '12').shortNumero, '12');
      expect(const CadastreParcel(idu: 'i').shortNumero, isNull);
    });

    test('contains the points inside its outlines', () {
      const parcel = CadastreParcel(
        idu: 'i',
        geometry: {
          'type': 'MultiPolygon',
          'coordinates': [
            [
              [
                [10.0, 10.0],
                [11.0, 10.0],
                [11.0, 11.0],
                [10.0, 11.0],
                [10.0, 10.0],
              ],
            ],
            [square],
          ],
        },
      );
      expect(parcel.contains(const GeoPoint(0.2, 0.8)), isTrue);
      expect(parcel.contains(const GeoPoint(10.5, 10.5)), isTrue);
      expect(parcel.contains(const GeoPoint(0.8, 0.2)), isFalse);
      expect(parcel.contains(const GeoPoint(5, 5)), isFalse);
      expect(
        const CadastreParcel(idu: 'i').contains(const GeoPoint(0, 0)),
        isFalse,
      );
    });

    group('outlines', () {
      const expected = [
        [GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(1, 1), GeoPoint(0, 0)],
      ];

      test('reads the outer rings of a MultiPolygon', () {
        const parcel = CadastreParcel(
          idu: 'i',
          geometry: {
            'type': 'MultiPolygon',
            'coordinates': [
              [square, square],
              <Object>[],
            ],
          },
        );
        expect(parcel.outlines, expected);
      });

      test('reads the outer ring of a Polygon', () {
        const parcel = CadastreParcel(
          idu: 'i',
          geometry: {
            'type': 'Polygon',
            'coordinates': [square],
          },
        );
        expect(parcel.outlines, expected);
      });

      test('is empty without a supported geometry', () {
        expect(const CadastreParcel(idu: 'i').outlines, isEmpty);
        expect(
          const CadastreParcel(
            idu: 'i',
            geometry: {'type': 'Point', 'coordinates': square},
          ).outlines,
          isEmpty,
        );
        expect(
          const CadastreParcel(
            idu: 'i',
            geometry: {'type': 'Polygon', 'coordinates': 'invalid'},
          ).outlines,
          isEmpty,
        );
      });
    });
  });
}
