import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/parcel_map.dart';

import '../../../../helpers/helpers.dart';
import '../location_fixtures.dart';

void main() {
  final tiles = <(int, int, int)>[];

  Widget tile(BuildContext context, int zoom, int x, int y) {
    tiles.add((zoom, x, y));
    return testTile(context, zoom, x, y);
  }

  setUp(() {
    usePhoneSurface();
    tiles.clear();
  });

  Future<void> pumpMap(
    WidgetTester tester, {
    GeoPoint center = testPoint,
    List<List<GeoPoint>>? outlines,
    ValueChanged<GeoPoint>? onTap,
    VoidCallback? onLocate,
    String? badge,
    bool isBusy = false,
    Object? fitKey,
    String? semanticTapLabel,
  }) => tester.pumpApp(
    ListView(
      padding: const EdgeInsets.only(top: 200),
      children: [
        SizedBox(
          width: 350,
          child: ParcelMap(
            fitKey: fitKey,
            semanticTapLabel: semanticTapLabel,
            center: center,
            outlines: outlines ?? testParcel.outlines,
            marker: testPoint,
            onTap: onTap,
            onLocate: onLocate,
            badge: badge,
            isBusy: isBusy,
            tileBuilder: tile,
          ),
        ),
        const SizedBox(height: 2000),
      ],
    ),
  );

  int zoom() => tiles.last.$1;

  testWidgets('shows the tiles around the center, fitted to the parcel', (
    tester,
  ) async {
    await pumpMap(
      tester,
      outlines: squareParcel(half: 0.0001).outlines,
      badge: 'Parcelle AB 98 sélectionnée',
    );
    expect(zoom(), ParcelMap.maxZoom);
    expect(tiles.map((t) => t.$2).toSet(), containsAll([269045, 269046]));
    expect(find.text('Parcelle AB 98 sélectionnée'), findsOneWidget);
    expect(find.text('© IGN'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Me géolocaliser'), findsNothing);
  });

  testWidgets('uses the default zoom without a parcel', (tester) async {
    await pumpMap(tester, outlines: const [], isBusy: true, badge: '…');
    expect(zoom(), ParcelMap.defaultZoom);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('zooms in and out within the IGN levels', (tester) async {
    await pumpMap(tester, outlines: const []);
    await tester.tap(find.bySemanticsLabel('Zoomer'));
    await tester.pump();
    expect(zoom(), 19);
    // Maximum reached: the button does nothing.
    await tester.tap(find.bySemanticsLabel('Zoomer'));
    await tester.pump();
    expect(zoom(), 19);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.bySemanticsLabel('Dézoomer'));
      await tester.pump();
    }
    expect(zoom(), ParcelMap.minZoom);
  });

  testWidgets('reports the tapped point', (tester) async {
    GeoPoint? tapped;
    await pumpMap(tester, onTap: (point) => tapped = point);
    await tester.tap(find.byType(ParcelMap));
    expect(tapped!.lat, closeTo(testPoint.lat, 1e-5));
    expect(tapped!.lng, closeTo(testPoint.lng, 1e-5));
  });

  testWidgets('pans with a drag', (tester) async {
    GeoPoint? tapped;
    await pumpMap(tester, onTap: (point) => tapped = point);
    await tester.drag(find.byType(ParcelMap), const Offset(-100, 0));
    await tester.pump();
    await tester.tap(find.byType(ParcelMap));
    expect(tapped!.lng, greaterThan(testPoint.lng + 1e-4));
  });

  testWidgets('recenters when the center changes', (tester) async {
    await pumpMap(tester, outlines: const []);
    await tester.tap(find.bySemanticsLabel('Zoomer'));
    await pumpMap(
      tester,
      center: const GeoPoint(45.8, 4.8),
      outlines: const [],
    );
    expect(zoom(), ParcelMap.defaultZoom);
  });

  testWidgets('has a "Me géolocaliser" button', (tester) async {
    var located = 0;
    await pumpMap(tester, onLocate: () => located++);
    await tester.tap(find.bySemanticsLabel('Me géolocaliser'));
    expect(located, 1);
  });

  testWidgets('builds IGN orthophoto tiles', (tester) async {
    expect(
      ParcelMap.ignOrthoUrl(19, 269046, 187132),
      'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile'
      '&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal'
      '&TILEMATRIXSET=PM&FORMAT=image/jpeg'
      '&TILEMATRIX=19&TILEROW=187132&TILECOL=269046',
    );
    await tester.pumpApp(
      Builder(builder: (context) => ParcelMap.ignOrthoTile(context, 1, 2, 3)),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, ParcelMap.ignOrthoUrl(1, 2, 3));
    expect(
      image.errorBuilder!(tester.element(find.byType(Image)), Error(), null),
      isA<SizedBox>(),
    );
  });

  testWidgets('centers on the parcel when fitting it', (tester) async {
    GeoPoint? tapped;
    // A parcel east of the address point.
    await pumpMap(
      tester,
      outlines: eastParcel.outlines,
      onTap: (point) => tapped = point,
    );
    await tester.tap(find.byType(ParcelMap));
    expect(tapped!.lng, closeTo(4.740179, 1e-5));
  });

  testWidgets('fits again when the fit key changes', (tester) async {
    await pumpMap(tester, outlines: const [], fitKey: 1);
    await tester.tap(find.bySemanticsLabel('Zoomer'));
    await pumpMap(tester, outlines: const []);
    await tester.pump();
    expect(zoom(), 19);
    await pumpMap(tester, outlines: const [], fitKey: 1);
    expect(zoom(), 19);
    await pumpMap(tester, outlines: const [], fitKey: 2);
    expect(zoom(), ParcelMap.defaultZoom);
  });

  testWidgets('pans vertically inside a scroll view', (tester) async {
    GeoPoint? tapped;
    await pumpMap(tester, onTap: (point) => tapped = point);
    final top = tester.getTopLeft(find.byType(ParcelMap)).dy;
    await tester.drag(find.byType(ParcelMap), const Offset(0, -80));
    await tester.pump();
    // The page did not scroll: the map moved instead.
    expect(tester.getTopLeft(find.byType(ParcelMap)).dy, top);
    await tester.tap(find.byType(ParcelMap));
    expect(tapped!.lat, lessThan(testPoint.lat - 1e-5));
  });

  testWidgets('zooms with a pinch', (tester) async {
    await pumpMap(tester, outlines: const []);
    final center = tester.getCenter(find.byType(ParcelMap));
    Future<void> pinch(double from, double to) async {
      final a = await tester.startGesture(center - Offset(from, 0));
      final b = await tester.startGesture(center + Offset(from, 0));
      await tester.pump();
      for (var i = 1; i <= 5; i++) {
        final d = from + (to - from) * i / 5;
        await a.moveTo(center - Offset(d, 0));
        await b.moveTo(center + Offset(d, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump();
    }

    await pinch(20, 120);
    final zoomedIn = zoom();
    expect(zoomedIn, greaterThan(ParcelMap.defaultZoom));
    await pinch(120, 20);
    expect(zoom(), lessThan(zoomedIn));
  });

  testWidgets('offers the tap as an accessibility action', (tester) async {
    GeoPoint? tapped;
    await pumpMap(
      tester,
      onTap: (point) => tapped = point,
      semanticTapLabel: 'Sélectionner la parcelle au centre de la carte',
    );
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byType(ClipRRect),
            matching: find.byType(Semantics),
          )
          .first,
    );
    semantics.properties.customSemanticsActions!.values.single();
    expect(tapped!.lat, closeTo(testPoint.lat, 1e-4));
  });
}
