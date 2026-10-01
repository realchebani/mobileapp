import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

export 'package:image_picker/image_picker.dart' show XFile;

/// Where a document file comes from.
enum DocumentSource {
  /// A photo taken with the camera ("Scanner").
  camera,

  /// A PDF or image from the files ("Importer" · Fichiers).
  files,

  /// An image from the photo library ("Importer" · Photothèque).
  photos,
}

/// Picks document files (behind an interface so that tests never reach the
/// platform channels).
abstract interface class DocumentPicker {
  /// Lets the user pick a file from [source]; null when cancelled.
  ///
  /// Throws [DocumentAccessDenied] when the user refused the access to the
  /// camera or the photos.
  Future<XFile?> pick(DocumentSource source);
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

/// [DocumentPicker] of the device: `image_picker` for the camera and the
/// photo library, `file_selector` for the files.
class PlatformDocumentPicker implements DocumentPicker {
  new({ImagePicker? imagePicker, FileOpener? openFile})
    : _imagePicker = imagePicker ?? ImagePicker(),
      _openFile = openFile ?? _openWithFileSelector;

  final ImagePicker _imagePicker;
  final FileOpener _openFile;

  /// Longest side of the photos, enough to read a document.
  static const maxPhotoSide = 2400.0;

  /// JPEG quality of the photos.
  static const photoQuality = 85;

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

  @override
  Future<XFile?> pick(DocumentSource source) async {
    try {
      return await switch (source) {
        DocumentSource.camera => _pickImage(ImageSource.camera),
        DocumentSource.photos => _pickImage(ImageSource.gallery),
        DocumentSource.files => _openFile(
          acceptedTypeGroups: const [fileTypes],
        ),
      };
    } on PlatformException catch (error, stackTrace) {
      // image_picker: camera_access_denied, photo_access_denied.
      if (error.code.endsWith('access_denied')) {
        Error.throwWithStackTrace(DocumentAccessDenied(error), stackTrace);
      }
      rethrow;
    }
  }

  Future<XFile?> _pickImage(ImageSource source) => _imagePicker.pickImage(
    source: source,
    maxWidth: maxPhotoSide,
    maxHeight: maxPhotoSide,
    imageQuality: photoQuality,
  );
}
