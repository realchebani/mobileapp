import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/photos/cubit/room_photos_cubit.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_capture.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_labels.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_tile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the photo screen of the room of [cubit] (full screen, above the
/// tunnel). Each photo kept is handed to [cubit], which sends it.
Future<void> showPhotoCapture(
  BuildContext context, {
  required RoomPhotosCubit cubit,
  required PhotoCamera camera,
  required PhotoProcessor processor,
  required TiltStream tilt,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: PhotoCapturePage(
          camera: camera,
          processor: processor,
          tilt: tilt,
        ),
      ),
    ),
  );
}

enum _CameraStatus { starting, ready, denied, unavailable }

/// EPIC-15 · Prise de vue: the camera preview with a rule-of-thirds grid, a
/// level, the instruction "Personne dans le champ"; every photo is checked
/// on the device (light, sharpness, tilt) and, when a defect is found,
/// shown for "Reprendre" / "Garder".
class PhotoCapturePage extends StatefulWidget {
  const new({
    required this.camera,
    required this.processor,
    required this.tilt,
    this.openUrl = launchUrl,
    super.key,
  });

  final PhotoCamera camera;
  final PhotoProcessor processor;
  final TiltStream tilt;

  /// Opens the iOS settings after a refused camera.
  final Future<bool> Function(Uri url) openUrl;

  @override
  State<PhotoCapturePage> createState() => _PhotoCapturePageState();
}

class _PhotoCapturePageState extends State<PhotoCapturePage> {
  _CameraStatus _status = _CameraStatus.starting;
  StreamSubscription<double>? _tiltSubscription;
  double? _tilt;
  bool _busy = false;
  int _kept = 0;

  /// A photo with defects, waiting for "Reprendre" / "Garder".
  ProcessedPhoto? _review;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
    _tiltSubscription = widget.tilt().listen(
      (tilt) {
        if (mounted) setState(() => _tilt = tilt);
      },
      // No level without the sensor.
      onError: (Object _) {},
    );
  }

  Future<void> _start() async {
    try {
      await widget.camera.initialize();
      if (mounted) setState(() => _status = _CameraStatus.ready);
    } on PhotoAccessDenied {
      if (mounted) setState(() => _status = _CameraStatus.denied);
    } on Object {
      if (mounted) setState(() => _status = _CameraStatus.unavailable);
    }
  }

  @override
  void dispose() {
    unawaited(_tiltSubscription?.cancel());
    unawaited(widget.camera.dispose());
    super.dispose();
  }

  Future<void> _shoot() async {
    final cubit = context.read<RoomPhotosCubit>();
    if (_busy) return;
    setState(() => _busy = true);
    final tilt = _tilt;
    try {
      final bytes = await widget.camera.takePicture();
      final processed = await widget.processor.process(
        bytes,
        tiltDegrees: tilt,
      );
      if (!mounted) return;
      if (processed.quality.issues.isEmpty) {
        _keep(cubit, processed);
      } else {
        setState(() => _review = processed);
      }
    } on Object {
      if (mounted) {
        showRealestySnackBar(
          context,
          context.l10n.photosCameraFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _keep(RoomPhotosCubit cubit, ProcessedPhoto processed) {
    cubit.addFromCamera(processed);
    setState(() {
      _review = null;
      _kept++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final canAdd = context.select<RoomPhotosCubit, bool>(
      (cubit) => cubit.state.canAdd,
    );
    final review = _review;
    return Scaffold(
      backgroundColor: c.nuit,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.sm,
                RealestySpacing.xs,
                RealestySpacing.sm,
                RealestySpacing.xs,
              ),
              child: Row(
                children: [
                  RealestyIconButton(
                    icon: RealestyIcons.close,
                    semanticLabel: l10n.photosCameraClose,
                    dark: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      l10n.photosCameraInstruction,
                      textAlign: TextAlign.center,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.nuitTexte,
                      ),
                    ),
                  ),
                  const SizedBox(width: RealestySpacing.minTouchTarget),
                ],
              ),
            ),
            Expanded(
              child: switch (_status) {
                _CameraStatus.starting => Center(
                  child: CircularProgressIndicator(color: c.lueur),
                ),
                _CameraStatus.ready when review != null => _Review(
                  photo: review,
                  onRetake: () => setState(() => _review = null),
                  onKeep: () => _keep(context.read<RoomPhotosCubit>(), review),
                ),
                _CameraStatus.ready => _Viewfinder(
                  camera: widget.camera,
                  tilt: _tilt,
                ),
                _CameraStatus.denied => _Unavailable(
                  message: l10n.photosCameraDenied,
                  action: l10n.photosCameraSettings,
                  onAction: () =>
                      unawaited(widget.openUrl(Uri.parse('app-settings:'))),
                ),
                _CameraStatus.unavailable => _Unavailable(
                  message: l10n.photosCameraUnavailable,
                ),
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RealestySpacing.gutter,
                vertical: RealestySpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.photosCameraKept(_kept),
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.nuitTexteDiscret,
                      ),
                    ),
                  ),
                  _Shutter(
                    semanticLabel: l10n.photosCameraShutter,
                    busy: _busy,
                    onPressed:
                        _status == _CameraStatus.ready &&
                            review == null &&
                            canAdd &&
                            !_busy
                        ? () => unawaited(_shoot())
                        : null,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: RealestyButton(
                        label: l10n.photosDone,
                        variant: RealestyButtonVariant.accent,
                        height: 44,
                        expand: false,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview with its grid and its level.
class _Viewfinder extends StatelessWidget {
  const new({required this.camera, required this.tilt});

  final PhotoCamera camera;
  final double? tilt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final tilt = this.tilt;
    final level = tilt == null || tilt.abs() <= PhotoChecks.maxTiltDegrees;
    return Center(
      child: AspectRatio(
        aspectRatio: camera.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            camera.preview(),
            IgnorePointer(child: CustomPaint(painter: _GridPainter(c.surface))),
            if (tilt != null)
              Center(
                child: Semantics(
                  label: level
                      ? l10n.photosCameraLevelOk
                      : l10n.photosCameraLevelTilted,
                  child: Transform.rotate(
                    angle: -tilt * math.pi / 180,
                    child: Container(
                      width: 120,
                      height: 3,
                      color: level ? c.vert : c.attention,
                    ),
                  ),
                ),
              ),
            if (!level)
              Positioned(
                left: 0,
                right: 0,
                bottom: RealestySpacing.md,
                child: Center(
                  child: RealestyBadge(
                    label: l10n.photosCameraLevelTilted,
                    variant: RealestyBadgeVariant.toComplete,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), paint)
        ..drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.color != color;
}

/// A photo with defects: "Reprendre" or "Garder quand même".
class _Review extends StatelessWidget {
  const new({
    required this.photo,
    required this.onRetake,
    required this.onKeep,
  });

  final ProcessedPhoto photo;
  final VoidCallback onRetake;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RealestyRadius.card),
              child: PhotoImage(bytes: photo.bytes, fit: BoxFit.contain),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.photosReviewMessage(
                photoIssuesLabel(l10n, photo.quality.issues),
              ),
              textAlign: TextAlign.center,
              style: RealestyTextStyles.body.copyWith(color: c.nuitTexte),
            ),
          ),
          Row(
            spacing: RealestySpacing.sm,
            children: [
              Expanded(
                child: RealestyButton(
                  label: l10n.photosReviewRetake,
                  variant: RealestyButtonVariant.accent,
                  onPressed: onRetake,
                ),
              ),
              Expanded(
                child: RealestyButton(
                  label: l10n.photosReviewKeep,
                  variant: RealestyButtonVariant.secondary,
                  onPressed: onKeep,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const new({required this.message, this.action, this.onAction});

  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Padding(
      padding: const EdgeInsets.all(RealestySpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: RealestySpacing.md,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: RealestyTextStyles.body.copyWith(color: c.nuitTexte),
          ),
          if (action case final action?)
            RealestyButton(
              label: action,
              variant: RealestyButtonVariant.accent,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}

/// The round shutter button.
class _Shutter extends StatelessWidget {
  const new({
    required this.semanticLabel,
    required this.busy,
    required this.onPressed,
  });

  final String semanticLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return RealestyPressable(
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.surface, width: 4),
        ),
        child: busy
            ? SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: c.lueur,
                ),
              )
            : Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                ),
              ),
      ),
    );
  }
}
