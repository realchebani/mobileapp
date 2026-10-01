import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

export 'package:image_picker/image_picker.dart' show XFile;

/// Where an imported document file comes from ("Importer").
enum DocumentSource {
  /// A PDF or image from the files ("Fichiers").
  files,

  /// An image from the photo library ("Photothèque").
  photos,
}

/// Picks and scans document files (behind an interface so that tests never
/// reach the platform channels).
abstract interface class DocumentPicker {
  /// Lets the user pick a file from [source]; null when cancelled.
  ///
  /// Throws [DocumentAccessDenied] when the user refused the access to the
  /// photos.
  Future<XFile?> pick(DocumentSource source);

  /// Lets the user scan up to [maxPages] pages with the camera, in order;
  /// null when cancelled.
  ///
  /// Throws [DocumentAccessDenied] when the user refused the access to the
  /// camera.
  Future<List<XFile>?> scanPages({required int maxPages});
}

/// The user refused the access to the camera or the photos.
final class DocumentAccessDenied implements Exception {
  const new(this.error);

  final Object error;

  @override
  String toString() => 'DocumentAccessDenied($error)';
}

/// Opens the system file picker, accepting `acceptedTypeGroups`.
typedef FileOpener = Future<XFile?> Function({
  List<file_selector.XTypeGroup> acceptedTypeGroups,
});

/// Opens the system document scanner (edge detection, perspective
/// correction) for up to `maxPages` pages; returns the paths of the JPEG
/// pages, or null when cancelled.
typedef SystemDocumentScanner = Future<List<String>?> Function(int maxPages);

/// Removes the files written by the [SystemDocumentScanner].
typedef ScannerCacheCleaner = Future<void> Function();

/// [DocumentPicker] of the device: the system document scanner (VisionKit on
/// iOS, ML Kit on Android) for the scans, `image_picker` for the photo
/// library (and the camera when the device has no document scanner),
/// `file_selector` for the files.
class PlatformDocumentPicker implements DocumentPicker {
  new({
    ImagePicker? imagePicker,
    FileOpener? openFile,
    SystemDocumentScanner? scanDocument,
    ScannerCacheCleaner? cleanScannerCache,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _openFile = openFile ?? _openWithFileSelector,
       _scanDocument = scanDocument ?? _scanWithSystemScanner,
       _cleanScannerCache = cleanScannerCache ?? _cleanSystemScannerCache;

  final ImagePicker _imagePicker;
  final FileOpener _openFile;
  final SystemDocumentScanner _scanDocument;
  final ScannerCacheCleaner _cleanScannerCache;

  /// Whether the device has no system document scanner: the pages are then
  /// photographed one at a time with the camera.
  bool _scannerUnavailable = false;

  /// Longest side of the photos, enough to read a document.
  static const maxPhotoSide = 2400.0;

  /// JPEG quality of the photos.
  static const photoQuality = 85;

  /// JPEG quality of the scanned pages (0–1).
  static const scanQuality = 0.85;

  /// The file types accepted by the `property-documents` bucket.
  static const fileTypes = file_selector.XTypeGroup(
    label: 'Documents',
    extensions: ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
    mimeTypes: [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/heif',
    ],
    uniformTypeIdentifiers: [
      'com.adobe.pdf',
      'public.jpeg',
      'public.png',
      'public.heic',
      'public.heif',
    ],
  );

  static Future<XFile?> _openWithFileSelector({
    List<file_selector.XTypeGroup> acceptedTypeGroups = const [],
  }) => file_selector.openFile(acceptedTypeGroups: acceptedTypeGroups);

  static Future<List<String>?> _scanWithSystemScanner(int maxPages) =>
      CunningDocumentScanner.getPictures(
        noOfPages: maxPages,
        scannerSource: ScannerSource.camera,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: scanQuality,
        ),
      );

  static Future<void> _cleanSystemScannerCache() =>
      CunningDocumentScanner.cleanCache();

  @override
  Future<XFile?> pick(DocumentSource source) => _guard(
    () => switch (source) {
      DocumentSource.photos => _pickImage(ImageSource.gallery),
      DocumentSource.files => _openFile(acceptedTypeGroups: const [fileTypes]),
    },
  );

  @override
  Future<List<XFile>?> scanPages({required int maxPages}) async {
    if (!_scannerUnavailable) {
      try {
        return await _scanWithScanner(maxPages);
      } on CunningDocumentScannerException catch (error, stackTrace) {
        if (error.code == 'permission_denied') {
          Error.throwWithStackTrace(DocumentAccessDenied(error), stackTrace);
        }
        if (error.code != 'UNAVAILABLE') rethrow;
        _scannerUnavailable = true;
      } on MissingPluginException {
        _scannerUnavailable = true;
      }
    }
    final photo = await _guard(() => _pickImage(ImageSource.camera));
    return photo == null ? null : [photo];
  }

  /// The pages of the system scanner, read into memory so that its files
  /// (identity documents…) do not stay on the device.
  Future<List<XFile>?> _scanWithScanner(int maxPages) async {
    final paths = await _scanDocument(maxPages);
    if (paths == null) return null;
    try {
      return [
        for (final (index, path) in paths.indexed)
          XFile.fromData(
            await XFile(path).readAsBytes(),
            name: 'page-${index + 1}.jpg',
            path: 'page-${index + 1}.jpg',
            mimeType: 'image/jpeg',
          ),
      ];
    } finally {
      try {
        await _cleanScannerCache();
      } on Object {
        // Best effort: the system purges the caches anyway.
      }
    }
  }

  /// Runs [pick], reporting a refused access as [DocumentAccessDenied].
  static Future<T> _guard<T>(Future<T> Function() pick) async {
    try {
      return await pick();
    } on PlatformException catch (error, stackTrace) {
      // image_picker: camera_access_denied, photo_access_denied.
      if (error.code.endsWith('access_denied')) {
        Error.throwWithStackTrace(DocumentAccessDenied(error), stackTrace);
      }
      rethrow;
    }
  }

  /// A photo, read into memory: the copy `image_picker` writes in the
  /// temporary directory (identity documents…) is deleted at once.
  Future<XFile?> _pickImage(ImageSource source) async {
    final photo = await _imagePicker.pickImage(
      source: source,
      maxWidth: maxPhotoSide,
      maxHeight: maxPhotoSide,
      imageQuality: photoQuality,
    );
    if (photo == null) return null;
    final bytes = await photo.readAsBytes();
    final name = photo.name;
    if (photo.path.isNotEmpty) {
      try {
        // Synchronous: a small local file.
        File(photo.path).deleteSync();
      } on FileSystemException {
        // Best effort: the system purges the temporary files anyway.
      }
    }
    return XFile.fromData(
      bytes,
      name: name,
      path: name,
      mimeType: photo.mimeType,
    );
  }
}
