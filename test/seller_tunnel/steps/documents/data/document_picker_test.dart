import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';

class _MockImagePicker extends Mock implements ImagePicker;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockImagePicker imagePicker;
  final photo = XFile.fromData(Uint8List(3), name: 'photo.jpg');

  setUpAll(() => registerFallbackValue(ImageSource.camera));

  setUp(() {
    imagePicker = _MockImagePicker();
    when(
      () => imagePicker.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => photo);
  });

  group(PlatformDocumentPicker, () {
    test('takes a reduced JPEG photo with the camera', () async {
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      expect(await picker.pick(DocumentSource.camera), photo);
      verify(
        () => imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: PlatformDocumentPicker.maxPhotoSide,
          maxHeight: PlatformDocumentPicker.maxPhotoSide,
          imageQuality: PlatformDocumentPicker.photoQuality,
        ),
      ).called(1);
    });

    test('picks a photo of the library', () async {
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      expect(await picker.pick(DocumentSource.photos), photo);
      verify(
        () => imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: any(named: 'maxWidth'),
          maxHeight: any(named: 'maxHeight'),
          imageQuality: any(named: 'imageQuality'),
        ),
      ).called(1);
    });

    test('opens a PDF or image file', () async {
      List<XTypeGroup>? groups;
      final file = XFile.fromData(Uint8List(3), name: 'titre.pdf');
      final picker = PlatformDocumentPicker(
        imagePicker: imagePicker,
        openFile: ({acceptedTypeGroups = const []}) async {
          groups = acceptedTypeGroups;
          return file;
        },
      );

      expect(await picker.pick(DocumentSource.files), file);
      expect(groups, [PlatformDocumentPicker.fileTypes]);
      expect(groups!.single.uniformTypeIdentifiers, contains('com.adobe.pdf'));
      expect(groups!.single.mimeTypes, contains('application/pdf'));
    });

    test('reports a refused access', () async {
      final error = PlatformException(code: 'camera_access_denied');
      when(
        () => imagePicker.pickImage(
          source: any(named: 'source'),
          maxWidth: any(named: 'maxWidth'),
          maxHeight: any(named: 'maxHeight'),
          imageQuality: any(named: 'imageQuality'),
        ),
      ).thenThrow(error);
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      await expectLater(
        picker.pick(DocumentSource.camera),
        throwsA(
          isA<DocumentAccessDenied>()
              .having((e) => e.error, 'error', error)
              .having((e) => e.toString(), 'toString', contains('camera')),
        ),
      );
    });

    test('rethrows other platform errors', () async {
      when(
        () => imagePicker.pickImage(
          source: any(named: 'source'),
          maxWidth: any(named: 'maxWidth'),
          maxHeight: any(named: 'maxHeight'),
          imageQuality: any(named: 'imageQuality'),
        ),
      ).thenThrow(PlatformException(code: 'invalid_image'));
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      await expectLater(
        picker.pick(DocumentSource.photos),
        throwsA(isA<PlatformException>()),
      );
    });

    test('uses the device pickers by default', () async {
      final picker = PlatformDocumentPicker();

      // No file picker plugin in tests: the call reaches the platform.
      await expectLater(picker.pick(DocumentSource.files), throwsA(anything));
    });
  });
}
