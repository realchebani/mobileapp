import 'package:geo_repository/geo_repository.dart';
import 'package:material_ui/material_ui.dart';

/// "12 rue de la Colombe" (Chaponost), as returned by the BAN.
const testPoint = GeoPoint(45.707956, 4.739579);

const testAddress = GeoAddress(
  id: '69043_jj2dze_00012',
  label: '12 rue de la Colombe 69630 Chaponost',
  point: testPoint,
  type: GeoAddressType.housenumber,
  name: '12 rue de la Colombe',
  housenumber: '12',
  street: 'rue de la Colombe',
  postcode: '69630',
  city: 'Chaponost',
  citycode: '69043',
);

/// A square parcel of side 2 × [half] degrees centered on [center].
CadastreParcel squareParcel({
  String idu = '69043000AB0098',
  String section = 'AB',
  String numero = '0098',
  int? areaM2 = 540,
  GeoPoint center = testPoint,
  double half = 0.0002,
}) => CadastreParcel(
  idu: idu,
  section: section,
  numero: numero,
  codeInsee: '69043',
  communeName: 'Chaponost',
  areaM2: areaM2,
  geometry: {
    'type': 'MultiPolygon',
    'coordinates': [
      [
        [
          [center.lng - half, center.lat - half],
          [center.lng + half, center.lat - half],
          [center.lng + half, center.lat + half],
          [center.lng - half, center.lat + half],
          [center.lng - half, center.lat - half],
        ],
      ],
    ],
  },
);

final CadastreParcel testParcel = squareParcel();

/// A neighbouring parcel, east of [testParcel].
final CadastreParcel eastParcel = squareParcel(
  idu: '69043000AB0099',
  numero: '0099',
  areaM2: 310,
  center: const GeoPoint(45.707956, 4.740179),
);

/// Offline map tiles.
Widget testTile(BuildContext context, int zoom, int x, int y) =>
    const ColoredBox(color: Color(0xFF6E7F5B));
