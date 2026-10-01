import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';

/// A noisy image (hard to compress, like a photo).
img.Image _noise(int width, int height) {
  final random = Random(42);
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return image;
}

Uint8List _jpeg(int width, int height) =>
    img.encodeJpg(_noise(width, height), quality: 95);

String _latin1(Uint8List bytes) => latin1.decode(bytes);

void main() {
  group('compressPage', () {
    const compression = (maxSide: 200, quality: 80);

    test('downscales the longest side of a landscape page', () {
      final page = img.decodeJpg(compressPage(_jpeg(400, 100), compression))!;
      expect((page.width, page.height), (200, 50));
    });

    test('downscales the longest side of a portrait page', () {
      final page = img.decodeJpg(compressPage(_jpeg(100, 400), compression))!;
      expect((page.width, page.height), (50, 200));
    });

    test('keeps a small page and turns a PNG into a JPEG', () {
      final png = img.encodePng(_noise(120, 80));
      final page = compressPage(png, compression);
      expect(img.JpegDecoder().isValidFile(page), isTrue);
      final decoded = img.decodeJpg(page)!;
      expect((decoded.width, decoded.height), (120, 80));
    });

    test('applies the orientation of the photo', () {
      final rotated = _noise(100, 40)..exif.imageIfd.orientation = 6;
      final page = img.decodeJpg(
        compressPage(img.encodeJpg(rotated), compression),
      )!;
      expect((page.width, page.height), (40, 100));
    });

    test('rejects an unreadable page', () {
      expect(
        () => compressPage(Uint8List(64), compression),
        throwsFormatException,
      );
    });
  });

  group('buildScanPdf', () {
    test('makes one A4-wide page per image, in order', () async {
      final pdf = await buildScanPdf([
        _jpeg(300, 600),
        _jpeg(600, 300),
      ], maxBytes: 20 * 1024 * 1024);
      final text = _latin1(pdf);

      expect(text, startsWith('%PDF-'));
      expect(text, contains('/Count 2'));
      // Portrait then landscape, drawn over the whole page.
      final portrait = text.indexOf('q 595.28 0 0 1190.56 0 0 cm');
      final landscape = text.indexOf('q 595.28 0 0 297.64 0 0 cm');
      expect(portrait, isNonNegative);
      expect(landscape, greaterThan(portrait));
      expect(text, contains('/DCTDecode'));
    });

    test('compresses more until the PDF fits', () async {
      final pages = [_jpeg(400, 400)];
      const sharp = (maxSide: 400, quality: 95);
      const small = (maxSide: 100, quality: 50);
      final sharpPdf = await buildScanPdf(
        pages,
        maxBytes: 1 << 30,
        compressions: const [sharp],
      );

      final pdf = await buildScanPdf(
        pages,
        maxBytes: sharpPdf.length - 1,
        compressions: const [sharp, small],
      );

      expect(pdf.length, lessThan(sharpPdf.length ~/ 4));
    });

    test('fails when even the smallest PDF is too large', () async {
      final pages = [_jpeg(200, 200)];
      const level = (maxSide: 200, quality: 80);
      final jpegBytes = compressPage(pages.single, level).length;

      // The images fit, not the PDF around them.
      await expectLater(
        buildScanPdf(pages, maxBytes: jpegBytes, compressions: const [level]),
        throwsA(isA<ScanTooLarge>()),
      );
      // The images do not fit.
      await expectLater(
        buildScanPdf(pages, maxBytes: 10, compressions: const [level]),
        throwsA(isA<ScanTooLarge>()),
      );
    });
  });

  test('$IsolateScanPdfBuilder builds the PDF in the background', () async {
    final pdf = await const IsolateScanPdfBuilder().build([
      _jpeg(100, 100),
    ], maxBytes: 20 * 1024 * 1024);

    expect(_latin1(pdf), contains('/Count 1'));
  });
}
