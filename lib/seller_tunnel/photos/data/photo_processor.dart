import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:image/image.dart' as img;
import 'package:property_repository/property_repository.dart';

/// A photo ready to upload: upright JPEG, its size and the checks made on
/// the device.
final class ProcessedPhoto extends Equatable {
  const new({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final PhotoQuality quality;

  @override
  List<Object?> get props => [bytes.length, width, height, quality];
}

/// Prepares the photos before upload (behind an interface so that widget
/// tests can skip the image processing).
abstract interface class PhotoProcessor {
  /// [bytes] (a JPEG, PNG… photo) upright, reduced and checked; [tiltDegrees]
  /// is the tilt of the phone when it was taken (camera only).
  ///
  /// Throws a [FormatException] when the image cannot be read.
  Future<ProcessedPhoto> process(Uint8List bytes, {double? tiltDegrees});
}

/// [PhotoProcessor] running [processPhoto] in a background isolate.
final class IsolatePhotoProcessor implements PhotoProcessor {
  const new();

  @override
  Future<ProcessedPhoto> process(Uint8List bytes, {double? tiltDegrees}) =>
      Isolate.run(() => processPhoto(bytes, tiltDegrees: tiltDegrees));
}

/// Thresholds of the on-device checks (v1, to calibrate on real photos:
/// plan EPIC-15 §4.4).
abstract final class PhotoChecks {
  /// Longest side of the uploaded photos.
  static const maxSide = 2048;

  /// JPEG quality of the uploaded photos.
  static const jpegQuality = 85;

  /// Width of the reduced grey image used by the checks.
  static const analysisSide = 512;

  /// Below this mean luminance (0–255) a photo is too dark.
  static const minBrightness = 60.0;

  /// Above this mean luminance a photo is overexposed.
  static const maxBrightness = 225.0;

  /// Below this variance of the Laplacian a photo is blurry.
  static const minSharpness = 40.0;

  /// Above this tilt (degrees) a photo is tilted.
  static const maxTiltDegrees = 6.0;
}

/// [bytes] upright, its longest side at most [PhotoChecks.maxSide], as a
/// JPEG, with its brightness, sharpness and tilt checks.
ProcessedPhoto processPhoto(Uint8List bytes, {double? tiltDegrees}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // The decoders throw range errors on truncated data.
    decoded = null;
  }
  if (decoded == null) throw const FormatException('Unreadable photo');
  final image = _fit(img.bakeOrientation(decoded), PhotoChecks.maxSide);
  final small = _fit(image, PhotoChecks.analysisSide);
  final brightness = _brightness(small);
  final sharpness = _sharpness(small);
  return ProcessedPhoto(
    bytes: img.encodeJpg(
      image,
      quality: PhotoChecks.jpegQuality,
      chroma: img.JpegChroma.yuv420,
    ),
    width: image.width,
    height: image.height,
    quality: PhotoQuality(
      brightness: _round(brightness),
      sharpness: _round(sharpness),
      tiltDegrees: tiltDegrees == null ? null : _round(tiltDegrees),
      issues: [
        if (brightness < PhotoChecks.minBrightness) PhotoQualityIssue.dark,
        if (brightness > PhotoChecks.maxBrightness)
          PhotoQualityIssue.overexposed,
        if (sharpness < PhotoChecks.minSharpness) PhotoQualityIssue.blurry,
        if (tiltDegrees != null &&
            tiltDegrees.abs() > PhotoChecks.maxTiltDegrees)
          PhotoQualityIssue.tilted,
      ],
    ),
  );
}

double _round(double value) => (value * 10).roundToDouble() / 10;

/// [image] with its longest side at most [side].
img.Image _fit(img.Image image, int side) {
  if (math.max(image.width, image.height) <= side) return image;
  return image.width >= image.height
      ? img.copyResize(
          image,
          width: side,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: side,
          interpolation: img.Interpolation.average,
        );
}

/// Luminance (0–255) of every pixel, row by row.
List<double> _luminances(img.Image image) => [
  for (final pixel in image)
    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b,
];

double _brightness(img.Image image) {
  final values = _luminances(image);
  return values.fold<double>(0, (sum, v) => sum + v) / values.length;
}

/// Variance of the Laplacian of the grey image: low when the photo is
/// blurry (few sharp edges).
double _sharpness(img.Image image) {
  final width = image.width;
  final height = image.height;
  if (width < 3 || height < 3) return 0;
  final grey = _luminances(image);
  final laplacians = <double>[
    for (var y = 1; y < height - 1; y++)
      for (var x = 1; x < width - 1; x++)
        4 * grey[y * width + x] -
            grey[(y - 1) * width + x] -
            grey[(y + 1) * width + x] -
            grey[y * width + x - 1] -
            grey[y * width + x + 1],
  ];
  final mean =
      laplacians.fold<double>(0, (sum, v) => sum + v) / laplacians.length;
  return laplacians.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) /
      laplacians.length;
}
