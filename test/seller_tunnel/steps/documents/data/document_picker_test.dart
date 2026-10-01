import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
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
  final photo = XFile.fromData(Uint8List(3), path: 'photo.jpg');

  setUpAll(() => registerFallbackValue(ImageSource.camera));

  void stubPickImage(Future<XFile?> Function() answer) => when(
    () => imagePicker.pickImage(
      source: any(named: 'source'),
      maxWidth: any(named: 'maxWidth'),
      maxHeight: any(named: 'maxHeight'),
      imageQuality: any(named: 'imageQuality'),
    ),
  ).thenAnswer((_) => answer());

  setUp(() {
    imagePicker = _MockImagePicker();
    stubPickImage(() async => photo);
  });

  group(PlatformDocumentPicker, () {
    test('picks a reduced JPEG photo of the library', () async {
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      final picked = await picker.pick(DocumentSource.photos);
      expect(picked!.name, 'photo.jpg');
      expect(await picked.readAsBytes(), [0, 0, 0]);
      verify(
        () => imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: PlatformDocumentPicker.maxPhotoSide,
          maxHeight: PlatformDocumentPicker.maxPhotoSide,
          imageQuality: PlatformDocumentPicker.photoQuality,
        ),
      ).called(1);
    });

    test('deletes the temporary copy of a photo once read', () async {
      final directory = Directory.systemTemp.createTempSync('photo');
      addTearDown(() => directory.deleteSync(recursive: true));
      final copy = File('${directory.path}/image_picker_1.jpg')
        ..writeAsBytesSync([4, 2]);
      stubPickImage(() async => XFile(copy.path, mimeType: 'image/jpeg'));
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      final picked = await picker.pick(DocumentSource.photos);

      expect(copy.existsSync(), isFalse);
      expect(picked!.name, 'image_picker_1.jpg');
      expect(picked.mimeType, 'image/jpeg');
      expect(await picked.readAsBytes(), [4, 2]);
    });

    test('ignores a temporary copy already gone', () async {
      final directory = Directory.systemTemp.createTempSync('photo');
      addTearDown(() => directory.deleteSync(recursive: true));
      final copy = File('${directory.path}/gone.jpg')..writeAsBytesSync([1]);
      stubPickImage(() async {
        final bytes = copy.readAsBytesSync();
        copy.deleteSync();
        return XFile.fromData(bytes, path: copy.path);
      });
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      expect(await picker.pick(DocumentSource.photos), isNotNull);
    });

    test('returns null when no photo is picked', () async {
      stubPickImage(() async => null);
      final picker = PlatformDocumentPicker(imagePicker: imagePicker);

      expect(await picker.pick(DocumentSource.photos), isNull);
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
      final error = PlatformException(code: 'photo_access_denied');
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
        picker.pick(DocumentSource.photos),
        throwsA(
          isA<DocumentAccessDenied>()
              .having((e) => e.error, 'error', error)
              .having((e) => e.toString(), 'toString', contains('photo')),
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

    group('scanPages', () {
      late Directory directory;
      late int cleanings;

      setUp(() {
        directory = Directory.systemTemp.createTempSync('scan');
        cleanings = 0;
      });

      tearDown(() => directory.deleteSync(recursive: true));

      String scanFile(String name, List<int> bytes) =>
          (File('${directory.path}/$name')..writeAsBytesSync(bytes)).path;

      PlatformDocumentPicker pickerScanning(
        Future<List<String>?> Function(int maxPages) scan, {
        Future<void> Function()? clean,
      }) => PlatformDocumentPicker(
        imagePicker: imagePicker,
        scanDocument: scan,
        cleanScannerCache:
            clean ??
            () async {
              cleanings++;
            },
      );

      test('reads the pages of the system scanner, then cleans it', () async {
        int? asked;
        final picker = pickerScanning((maxPages) async {
          asked = maxPages;
          return [
            scanFile('a.jpg', [1, 2]),
            scanFile('b.jpg', [3]),
          ];
        });

        final pages = await picker.scanPages(maxPages: 12);

        expect(asked, 12);
        expect(pages!.map((page) => page.name), ['page-1.jpg', 'page-2.jpg']);
        expect(pages.first.mimeType, 'image/jpeg');
        expect(await pages.first.readAsBytes(), [1, 2]);
        expect(await pages.last.readAsBytes(), [3]);
        expect(cleanings, 1);
        verifyNever(
          () => imagePicker.pickImage(
            source: any(named: 'source'),
            maxWidth: any(named: 'maxWidth'),
            maxHeight: any(named: 'maxHeight'),
            imageQuality: any(named: 'imageQuality'),
          ),
        );
      });

      test('returns null when the scan is cancelled', () async {
        final picker = pickerScanning((_) async => null);

        expect(await picker.scanPages(maxPages: 3), isNull);
        expect(cleanings, 0);
      });

      test('ignores a failed cleaning', () async {
        final picker = pickerScanning(
          (_) async => [
            scanFile('a.jpg', [1]),
          ],
          clean: () async => throw Exception('busy'),
        );

        expect(await picker.scanPages(maxPages: 3), hasLength(1));
      });

      test('cleans the scanner even when a page cannot be read', () async {
        final picker = pickerScanning(
          (_) async => ['${directory.path}/missing.jpg'],
        );

        await expectLater(
          picker.scanPages(maxPages: 3),
          throwsA(isA<Exception>()),
        );
        expect(cleanings, 1);
      });

      test('reports a refused camera access', () async {
        const error = CunningDocumentScannerException.permissionDenied();
        final picker = pickerScanning((_) async => throw error);

        await expectLater(
          picker.scanPages(maxPages: 3),
          throwsA(
            isA<DocumentAccessDenied>().having((e) => e.error, 'error', error),
          ),
        );
      });

      test('rethrows other scanner errors', () async {
        final picker = pickerScanning(
          (_) async => throw const CunningDocumentScannerException(
            'boom',
            code: 'ERROR',
          ),
        );

        await expectLater(
          picker.scanPages(maxPages: 3),
          throwsA(isA<CunningDocumentScannerException>()),
        );
      });

      for (final (name, error) in [
        (
          'unavailable',
          const CunningDocumentScannerException('no', code: 'UNAVAILABLE'),
        ),
        ('missing', MissingPluginException()),
      ]) {
        test('falls back to the camera when the scanner is $name', () async {
          var scans = 0;
          final picker = pickerScanning((_) async {
            scans++;
            throw error;
          });

          final pages = await picker.scanPages(maxPages: 3);
          expect(pages!.single.name, 'photo.jpg');
          // The scanner is not tried again.
          stubPickImage(() async => null);
          expect(await picker.scanPages(maxPages: 3), isNull);
          expect(scans, 1);
          verify(
            () => imagePicker.pickImage(
              source: ImageSource.camera,
              maxWidth: PlatformDocumentPicker.maxPhotoSide,
              maxHeight: PlatformDocumentPicker.maxPhotoSide,
              imageQuality: PlatformDocumentPicker.photoQuality,
            ),
          ).called(2);
        });
      }

      test('reports a refused access to the fallback camera', () async {
        when(
          () => imagePicker.pickImage(
            source: any(named: 'source'),
            maxWidth: any(named: 'maxWidth'),
            maxHeight: any(named: 'maxHeight'),
            imageQuality: any(named: 'imageQuality'),
          ),
        ).thenThrow(PlatformException(code: 'camera_access_denied'));
        final picker = pickerScanning(
          (_) async => throw MissingPluginException(),
        );

        await expectLater(
          picker.scanPages(maxPages: 3),
          throwsA(isA<DocumentAccessDenied>()),
        );
      });

      test('uses the system scanner by default', () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('cunning_document_scanner'),
              (call) async {
                calls.add(call);
                return call.method == 'getPictures'
                    ? [
                        scanFile('a.jpg', [7]),
                      ]
                    : null;
              },
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('cunning_document_scanner'),
                null,
              ),
        );

        final pages = await PlatformDocumentPicker(imagePicker: imagePicker)
            .scanPages(maxPages: 4);

        expect(pages, hasLength(1));
        expect(calls.map((call) => call.method), ['getPictures', 'cleanCache']);
        final arguments = calls.first.arguments as Map<Object?, Object?>;
        expect(arguments['noOfPages'], 4);
        expect(arguments['scannerSource'], 'camera');
        expect(arguments['iosScannerOptions'], {
          'imageFormat': 'jpg',
          'jpgCompressionQuality': PlatformDocumentPicker.scanQuality,
          'defaultFilter': 'original',
          'showFilterBar': true,
        });
      });
    });
  });
}
