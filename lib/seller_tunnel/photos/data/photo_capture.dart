import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// The user refused the access to the camera or to the photos.
final class PhotoAccessDenied implements Exception {
  const new(this.error);

  final Object error;

  @override
  String toString() => 'PhotoAccessDenied($error)';
}

/// The camera of the photo screen (behind an interface so that tests never
/// reach the platform channels).
abstract interface class PhotoCamera {
  /// Opens the back camera.
  ///
  /// Throws [PhotoAccessDenied] when the user refused the camera.
  Future<void> initialize();

  /// Width / height of the preview (portrait).
  double get aspectRatio;

  /// The live preview, once [initialize]d.
  Widget preview();

  /// Takes a photo and returns its bytes (the temporary file is deleted).
  Future<Uint8List> takePicture();

  Future<void> dispose();
}

/// Lists the cameras of the device.
typedef CameraLister = Future<List<CameraDescription>> Function();

/// Builds the controller of a camera.
typedef CameraControllerFactory = CameraController Function(
  CameraDescription description,
);

/// [PhotoCamera] of the `camera` plugin (BSD-3): the back camera, Full HD,
/// without audio, JPEG.
class PluginPhotoCamera implements PhotoCamera {
  new({CameraLister? listCameras, CameraControllerFactory? createController})
    : _listCameras = listCameras ?? availableCameras,
      _createController = createController ?? defaultController;

  final CameraLister _listCameras;
  final CameraControllerFactory _createController;
  CameraController? _controller;

  /// The controller of [description]: Full HD, no audio, JPEG.
  static CameraController defaultController(CameraDescription description) =>
      CameraController(
        description,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

  /// Codes of `CameraException` for a refused camera.
  static const deniedCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  CameraController get _ready {
    final controller = _controller;
    if (controller == null) throw StateError('Camera not initialized');
    return controller;
  }

  @override
  Future<void> initialize() async {
    try {
      final cameras = await _listCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera on this device');
      }
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = _controller = _createController(back);
      await controller.initialize();
    } on CameraException catch (error, stackTrace) {
      if (deniedCodes.contains(error.code)) {
        Error.throwWithStackTrace(PhotoAccessDenied(error), stackTrace);
      }
      rethrow;
    }
  }

  @override
  double get aspectRatio {
    final ratio = _ready.value.aspectRatio;
    // The plugin reports landscape ratios; the screen is portrait.
    return ratio > 1 ? 1 / ratio : ratio;
  }

  @override
  Widget preview() => CameraPreview(_ready);

  @override
  Future<Uint8List> takePicture() async {
    final file = await _ready.takePicture();
    final bytes = await file.readAsBytes();
    if (file.path.isNotEmpty) {
      try {
        File(file.path).deleteSync();
      } on FileSystemException {
        // Best effort: the system purges the temporary files anyway.
      }
    }
    return bytes;
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
  }
}

/// Photos of the photo library (behind an interface for the tests).
abstract interface class PhotoLibrary {
  /// Lets the user pick up to [limit] photos; empty when cancelled.
  ///
  /// Throws [PhotoAccessDenied] when the user refused the photos.
  Future<List<Uint8List>> pick({required int limit});
}

/// [PhotoLibrary] of `image_picker`: JPEG photos reduced to 2 048 px by the
/// system, read into memory (the temporary copies are deleted).
class ImagePickerPhotoLibrary implements PhotoLibrary {
  new({ImagePicker? imagePicker}) : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// Longest side asked to the system.
  static const maxSide = 2048.0;

  /// JPEG quality asked to the system.
  static const quality = 90;

  @override
  Future<List<Uint8List>> pick({required int limit}) async {
    if (limit < 1) return const [];
    final List<XFile> files;
    try {
      files = limit == 1
          ? [
              ?await _imagePicker.pickImage(
                source: ImageSource.gallery,
                maxWidth: maxSide,
                maxHeight: maxSide,
                imageQuality: quality,
              ),
            ]
          : await _imagePicker.pickMultiImage(
              maxWidth: maxSide,
              maxHeight: maxSide,
              imageQuality: quality,
              limit: limit,
            );
    } on PlatformException catch (error, stackTrace) {
      if (error.code.endsWith('access_denied')) {
        Error.throwWithStackTrace(PhotoAccessDenied(error), stackTrace);
      }
      rethrow;
    }
    return [for (final file in files.take(limit)) await _read(file)];
  }

  static Future<Uint8List> _read(XFile file) async {
    final bytes = await file.readAsBytes();
    if (file.path.isNotEmpty) {
      try {
        File(file.path).deleteSync();
      } on FileSystemException {
        // Best effort.
      }
    }
    return bytes;
  }
}

/// The tilt of the phone around the axis facing the user, in degrees,
/// relative to the nearest upright position (portrait or landscape): 0 when
/// the photo is level.
double tiltDegrees(double x, double y) {
  final angle = math.atan2(x, y) * 180 / math.pi;
  return ((angle + 45) % 90 + 90) % 90 - 45;
}

/// The tilt of the phone over time (degrees, see [tiltDegrees]).
typedef TiltStream = Stream<double> Function();

/// [TiltStream] of the accelerometer (`sensors_plus`, BSD-3).
Stream<double> accelerometerTilt() =>
    accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .map((event) => tiltDegrees(event.x, event.y));
