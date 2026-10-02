import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:property_repository/property_repository.dart';

/// A [width] × [height] JPEG: a checkerboard of [size] px squares (sharp)
/// of [dark] and [light] grey, or a flat [light] grey without squares.
Uint8List _jpeg(
  int width,
  int height, {
  int dark = 40,
  int light = 200,
  int? size = 8,
}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    final on = size != null && ((pixel.x ~/ size) + (pixel.y ~/ size)).isEven;
    final v = on ? dark : light;
    pixel
      ..r = v
      ..g = v
      ..b = v;
  }
  return img.encodeJpg(image, quality: 95);
}

void main() {
  group('processPhoto', () {
    test('keeps a sharp, well lit photo as is', () {
      final photo = processPhoto(_jpeg(400, 300), tiltDegrees: 2.04);
      expect(photo.width, 400);
      expect(photo.height, 300);
      expect(img.decodeJpg(photo.bytes), isNotNull);
      expect(photo.quality.issues, isEmpty);
      expect(photo.quality.tiltDegrees, 2);
      expect(photo.quality.brightness, inInclusiveRange(100, 140));
      expect(photo.quality.sharpness, greaterThan(PhotoChecks.minSharpness));
    });

    test('reduces a large photo to 2048 px, landscape or portrait', () {
      final landscape = processPhoto(_jpeg(2600, 1300, size: 64));
      expect((landscape.width, landscape.height), (2048, 1024));
      final portrait = processPhoto(_jpeg(1300, 2600, size: 64));
      expect((portrait.width, portrait.height), (1024, 2048));
    });

    test('finds a dark, blurry and tilted photo', () {
      final photo = processPhoto(
        _jpeg(300, 200, light: 20, size: null),
        tiltDegrees: -9,
      );
      expect(photo.quality.issues, [
        PhotoQualityIssue.dark,
        PhotoQualityIssue.blurry,
        PhotoQualityIssue.tilted,
      ]);
      expect(photo.quality.tiltDegrees, -9);
    });

    test('finds an overexposed photo', () {
      final photo = processPhoto(_jpeg(300, 200, dark: 250, light: 252));
      expect(photo.quality.issues, contains(PhotoQualityIssue.overexposed));
      expect(photo.quality.tiltDegrees, isNull);
    });

    test('a tiny photo has no measurable sharpness', () {
      final photo = processPhoto(_jpeg(2, 2));
      expect(photo.quality.sharpness, 0);
    });

    test('rejects an unreadable image', () {
      expect(
        () => processPhoto(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(
        () => processPhoto(Uint8List.fromList(List.filled(64, 7))),
        throwsFormatException,
      );
    });
  });

  group('privacy', () {
    /// A JPEG carrying a GPS position and the device make.
    Uint8List located() {
      final image = img.Image(width: 64, height: 48);
      image.exif.imageIfd
        ..make = 'Apple'
        ..model = 'iPhone 14 Plus';
      image.exif.gpsIfd
        ..gpsLatitude = 45.7
        ..gpsLongitude = 4.75;
      final jpeg = img.encodeJpg(image);
      final check = img.decodeJpg(jpeg)!;
      expect(check.exif.gpsIfd.hasGPSLatitude, isTrue);
      expect(check.exif.imageIfd.make, 'Apple');
      return jpeg;
    }

    void expectNoMetadata(Uint8List jpeg) {
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.exif.gpsIfd.hasGPSLatitude, isFalse);
      expect(decoded.exif.gpsIfd.hasGPSLongitude, isFalse);
      expect(decoded.exif.imageIfd.make, isNull);
      expect(decoded.exif.imageIfd.model, isNull);
      expect(decoded.exif.isEmpty, isTrue);
    }

    test('a photo keeps no GPS position nor device', () {
      expectNoMetadata(processPhoto(located()).bytes);
    });

    test('a plan or scanned page keeps none either', () {
      expectNoMetadata(compressPage(located(), (maxSide: 2400, quality: 85)));
    });
  });

  test('IsolatePhotoProcessor processes in the background', () async {
    final photo = await const IsolatePhotoProcessor().process(
      _jpeg(64, 48),
      tiltDegrees: 1,
    );
    expect(photo.width, 64);
    expect(photo.quality.tiltDegrees, 1);
    expect(
      photo,
      ProcessedPhoto(
        bytes: photo.bytes,
        width: 64,
        height: 48,
        quality: photo.quality,
      ),
    );
  });
}
