import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/web_mercator.dart';
import 'package:mobileapp/ui/ui.dart';

/// Builds the image of the tile [x], [y] at [zoom] (Web Mercator, 256 px).
typedef MapTileBuilder = Widget Function(
  BuildContext context,
  int zoom,
  int x,
  int y,
);

/// V2 aerial map (spec: h210, radius 16): IGN orthophoto tiles, the
/// selected parcel outlines, the address point, zoom and "Me géolocaliser"
/// buttons and a badge.
///
/// A small self-contained tile map (no map package: the usual ones pull
/// dependencies whose licenses the project does not allow). Drag (in any
/// direction, even inside a scroll view) to pan, pinch to zoom, tap to
/// report a point with [onTap].
class ParcelMap extends StatefulWidget {
  const new({
    required this.center,
    this.outlines = const [],
    this.marker,
    this.onTap,
    this.onLocate,
    this.badge,
    this.isBusy = false,
    this.fitKey,
    this.semanticTapLabel,
    this.tileBuilder = ignOrthoTile,
    super.key,
  });

  /// Center used when there are no [outlines]; the view recenters (and
  /// fits the [outlines]) when it changes.
  final GeoPoint center;

  /// The view also fits the [outlines] again when this changes to another
  /// non-null value (null: keep the current view, e.g. while editing).
  final Object? fitKey;

  /// Accessibility action applying [onTap] to the center of the map (the
  /// map itself cannot be explored by screen readers).
  final String? semanticTapLabel;

  /// Outer rings of the selected parcels.
  final List<List<GeoPoint>> outlines;

  /// The address point.
  final GeoPoint? marker;

  /// Called with the point tapped.
  final ValueChanged<GeoPoint>? onTap;

  /// "Me géolocaliser" button (hidden when null).
  final VoidCallback? onLocate;

  /// Bottom-left badge, e.g. "Parcelle AB 98 sélectionnée".
  final String? badge;

  /// Shows a spinner in the badge.
  final bool isBusy;

  /// Tile images; defaults to [ignOrthoTile]. Tests inject offline tiles.
  final MapTileBuilder tileBuilder;

  static const height = 210.0;
  static const minZoom = 14;

  /// Highest zoom of the IGN orthophotos.
  static const maxZoom = 19;

  /// Zoom used when there is no parcel to fit.
  static const defaultZoom = 18;

  /// URL of an IGN orthophoto tile (Géoplateforme WMTS, no key needed).
  static String ignOrthoUrl(int zoom, int x, int y) =>
      'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile'
      '&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal'
      '&TILEMATRIXSET=PM&FORMAT=image/jpeg'
      '&TILEMATRIX=$zoom&TILEROW=$y&TILECOL=$x';

  /// Network IGN orthophoto tile (blank on error, e.g. offline).
  static Widget ignOrthoTile(BuildContext context, int zoom, int x, int y) =>
      Image.network(
        ignOrthoUrl(zoom, x, y),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );

  @override
  State<ParcelMap> createState() => _ParcelMapState();
}

class _ParcelMapState extends State<ParcelMap> {
  late GeoPoint _center = widget.center;
  late Object? _fitKey = widget.fitKey;
  int? _zoom;

  /// Pinch scale at the last zoom step.
  double _scaleBase = 1;

  /// Pinch ratio that changes the zoom by one level.
  static const _pinchStep = 1.6;

  @override
  void didUpdateWidget(ParcelMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fitKey = widget.fitKey;
    final refit = fitKey != null && fitKey != _fitKey;
    if (fitKey != null) _fitKey = fitKey;
    if (refit || widget.center != oldWidget.center) {
      _center = widget.center;
      _zoom = null;
    }
  }

  void _zoomBy(int delta) => setState(
    () => _zoom = (_zoom! + delta).clamp(ParcelMap.minZoom, ParcelMap.maxZoom),
  );

  /// Fits the [ParcelMap.outlines] in [size]: zoom and center.
  int _fit(Size size) {
    final points = widget.outlines.expand((ring) => ring);
    if (WebMercator.boundsCenter(points) case final center?) _center = center;
    return WebMercator.fitZoom(
      points,
      size,
      minZoom: ParcelMap.minZoom,
      maxZoom: widget.outlines.isEmpty
          ? ParcelMap.defaultZoom
          : ParcelMap.maxZoom,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details, int zoom) {
    setState(() {
      _center = WebMercator.unproject(
        WebMercator.project(_center, zoom) - details.focalPointDelta,
        zoom,
      );
      if (details.pointerCount < 2) return;
      final ratio = details.scale / _scaleBase;
      if (ratio >= _pinchStep || ratio <= 1 / _pinchStep) {
        _scaleBase = details.scale;
        _zoom = (zoom + (ratio > 1 ? 1 : -1)).clamp(
          ParcelMap.minZoom,
          ParcelMap.maxZoom,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final onTap = widget.onTap;
    final tapLabel = widget.semanticTapLabel;
    return Semantics(
      container: true,
      label: l10n.locationMapLabel,
      customSemanticsActions: onTap == null || tapLabel == null
          ? null
          : {CustomSemanticsAction(label: tapLabel): () => onTap(_center)},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        child: SizedBox(
          height: ParcelMap.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final zoom = _zoom ??= _fit(size);
              final origin =
                  WebMercator.project(_center, zoom) -
                  Offset(size.width / 2, size.height / 2);
              return Stack(
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      // A smaller slop than the page's scroll view: drags
                      // starting on the map pan it, vertically too.
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          gestureSettings: const DeviceGestureSettings(
                            touchSlop: kTouchSlop / 3,
                          ),
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: onTap == null
                              ? null
                              : (details) => onTap(
                                  WebMercator.unproject(
                                    origin + details.localPosition,
                                    zoom,
                                  ),
                                ),
                          onScaleStart: (_) => _scaleBase = 1,
                          onScaleUpdate: (details) =>
                              _onScaleUpdate(details, zoom),
                          child: ColoredBox(
                            color: c.imagePlaceholder,
                            child: Stack(
                              children: [
                                ..._tiles(context, zoom, origin, size),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _OutlinePainter(
                                      rings: [
                                        for (final ring in widget.outlines)
                                          [
                                            for (final point in ring)
                                              WebMercator.project(point, zoom) -
                                                  origin,
                                          ],
                                      ],
                                      fill: c.vert.withValues(alpha: 0.34),
                                      stroke: c.lueur,
                                    ),
                                  ),
                                ),
                                if (widget.marker case final marker?)
                                  _marker(
                                    c,
                                    WebMercator.project(marker, zoom) - origin,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Column(
                      spacing: RealestySpacing.xs,
                      children: [
                        if (widget.onLocate != null)
                          RealestyIconButton(
                            icon: RealestyIcons.target,
                            semanticLabel: l10n.locationLocateMe,
                            onPressed: widget.onLocate,
                          ),
                        RealestyIconButton(
                          icon: RealestyIcons.plus,
                          semanticLabel: l10n.locationZoomIn,
                          onPressed: zoom < ParcelMap.maxZoom
                              ? () => _zoomBy(1)
                              : null,
                        ),
                        RealestyIconButton(
                          icon: RealestyIcons.minus,
                          semanticLabel: l10n.locationZoomOut,
                          onPressed: zoom > ParcelMap.minZoom
                              ? () => _zoomBy(-1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (widget.badge case final badge?)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      right: 60,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Badge(label: badge, isBusy: widget.isBusy),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 6,
                    child: Text(
                      l10n.locationMapAttribution,
                      style: RealestyTextStyles.tag.copyWith(
                        color: c.surface,
                        shadows: [Shadow(color: c.encre, blurRadius: 3)],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _tiles(
    BuildContext context,
    int zoom,
    Offset origin,
    Size size,
  ) {
    const tileSize = WebMercator.tileSize;
    final count = 1 << zoom;
    final first = origin / tileSize;
    final last = (origin + Offset(size.width, size.height)) / tileSize;
    return [
      for (
        var y = math.max(first.dy.floor(), 0);
        y <= math.min(last.dy.floor(), count - 1);
        y++
      )
        for (var x = first.dx.floor(); x <= last.dx.floor(); x++)
          Positioned(
            key: ValueKey((zoom, x, y)),
            left: x * tileSize - origin.dx,
            top: y * tileSize - origin.dy,
            width: tileSize,
            height: tileSize,
            child: widget.tileBuilder(context, zoom, x % count, y),
          ),
    ];
  }

  Widget _marker(RealestyColors c, Offset position) {
    const size = 18.0;
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.encre, width: 4),
          boxShadow: RealestyShadows.level1,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new({required this.label, required this.isBusy});

  final String label;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      liveRegion: true,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.encre,
          borderRadius: BorderRadius.circular(RealestyRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            if (isBusy)
              SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.surface,
                ),
              )
            else
              RealestyIcon(RealestyIcons.pin, size: 14, color: c.surface),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RealestyTextStyles.badge.copyWith(color: c.surface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  const new({required this.rings, required this.fill, required this.stroke});

  final List<List<Offset>> rings;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = fill;
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeJoin = StrokeJoin.round;
    for (final ring in rings) {
      final path = Path()..addPolygon(ring, true);
      canvas
        ..drawPath(path, fillPaint)
        ..drawPath(path, strokePaint);
    }
  }

  /// The rings are projected again on every build (pan, zoom, selection).
  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) => true;
}
