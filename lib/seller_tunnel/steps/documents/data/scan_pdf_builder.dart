import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

/// Combines the pages of a scan into one PDF (behind an interface so that
/// tests can skip the image processing).
abstract interface class ScanPdfBuilder {
  /// One PDF of [pages] (JPEG or PNG images, in order), at most [maxBytes].
  ///
  /// Throws [ScanTooLarge] when even the most compressed PDF is larger, and
  /// a [FormatException] when a page cannot be read.
  Future<Uint8List> build(List<Uint8List> pages, {required int maxBytes});
}

/// The pages do not fit in the size limit, even compressed.
final class ScanTooLarge implements Exception {
  const new();
}

/// A compression level of the pages: longest side and JPEG quality.
typedef ScanCompression = ({int maxSide, int quality});

/// [ScanPdfBuilder] running [buildScanPdf] in a background isolate.
final class IsolateScanPdfBuilder implements ScanPdfBuilder {
  const new();

  @override
  Future<Uint8List> build(List<Uint8List> pages, {required int maxBytes}) =>
      Isolate.run(() => buildScanPdf(pages, maxBytes: maxBytes));
}

/// Compression levels tried in order until the PDF fits: the first one
/// keeps the documents sharp (about 240 dpi on an A4 page).
const List<ScanCompression> scanCompressions = [
  (maxSide: 2000, quality: 80),
  (maxSide: 1600, quality: 70),
  (maxSide: 1240, quality: 60),
  (maxSide: 1000, quality: 50),
];

/// Width of the PDF pages (A4), in points; their height follows the image.
const scanPageWidth = 595.28;

/// One PDF of [pages], each page re-encoded (upright, downscaled, JPEG) at
/// the first of [compressions] whose PDF is at most [maxBytes].
Future<Uint8List> buildScanPdf(
  List<Uint8List> pages, {
  required int maxBytes,
  List<ScanCompression> compressions = scanCompressions,
}) async {
  for (final compression in compressions) {
    final jpegs = [for (final page in pages) compressPage(page, compression)];
    final imagesBytes = jpegs.fold(0, (sum, jpeg) => sum + jpeg.length);
    if (imagesBytes > maxBytes) continue;
    final pdf = await _pdfOf(jpegs);
    if (pdf.length <= maxBytes) return pdf;
  }
  throw const ScanTooLarge();
}

/// [page] upright, its longest side at most `maxSide`, as a JPEG.
Uint8List compressPage(Uint8List page, ScanCompression compression) {
  final decoded = img.decodeImage(page);
  if (decoded == null) throw const FormatException('Unreadable page');
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > compression.maxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: compression.maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: compression.maxSide,
            interpolation: img.Interpolation.average,
          );
  }
  return img.encodeJpg(
    image,
    quality: compression.quality,
    chroma: img.JpegChroma.yuv420,
  );
}

Future<Uint8List> _pdfOf(List<Uint8List> jpegs) async {
  final document = PdfDocument();
  for (final jpeg in jpegs) {
    final image = PdfImage.jpeg(document, image: jpeg);
    final height = scanPageWidth * image.height / image.width;
    PdfPage(
      document,
      pageFormat: PdfPageFormat(scanPageWidth, height),
    ).getGraphics().drawImage(image, 0, 0, scanPageWidth, height);
  }
  return Uint8List.fromList(await document.save());
}
