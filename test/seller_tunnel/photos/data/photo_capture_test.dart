import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:mobileapp/seller_tunnel/photos/data/photo_capture.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements CameraController;

class _MockImagePicker extends Mock implements picker.ImagePicker;

const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(PluginPhotoCamera, () {
    late _MockController controller;
    late List<CameraDescription> created;

    PluginPhotoCamera camera({
      List<CameraDescription> cameras = const [_back],
    }) {
      created = [];
      return PluginPhotoCamera(
        listCameras: () async => cameras,
        createController: (description) {
          created.add(description);
          return controller;
        },
      );
    }

    setUp(() {
      controller = _MockController();
      when(() => controller.initialize()).thenAnswer((_) async {});
      when(() => controller.dispose()).thenAnswer((_) async {});
    });

    test('opens the back camera', () async {
      await camera(cameras: const [_front, _back]).initialize();
      expect(created, [_back]);
      verify(() => controller.initialize()).called(1);
    });

    test('falls back to the first camera', () async {
      await camera(cameras: const [_front]).initialize();
      expect(created, [_front]);
    });

    test('reports a device without camera', () async {
      await expectLater(
        camera(cameras: const []).initialize(),
        throwsA(isA<CameraException>()),
      );
    });

    test('reports a refused camera', () async {
      when(() => controller.initialize())
          .thenThrow(CameraException('CameraAccessDenied', 'no'));
      await expectLater(
        camera().initialize(),
        throwsA(isA<PhotoAccessDenied>()),
      );
      expect(
        PhotoAccessDenied(CameraException('x', 'y')).toString(),
        startsWith('PhotoAccessDenied('),
      );
    });

    test('rethrows other camera errors', () async {
      when(() => controller.initialize())
          .thenThrow(CameraException('CameraError', 'no'));
      await expectLater(camera().initialize(), throwsA(isA<CameraException>()));
    });

    test('needs to be initialized', () {
      expect(() => camera().aspectRatio, throwsStateError);
    });

    test('gives a portrait aspect ratio', () async {
      final photoCamera = camera();
      await photoCamera.initialize();
      when(() => controller.value).thenReturn(
        const CameraValue.uninitialized(_back)
            .copyWith(previewSize: const Size(1920, 1080)),
      );
      expect(photoCamera.aspectRatio, closeTo(1080 / 1920, 1e-9));
      when(() => controller.value).thenReturn(
        const CameraValue.uninitialized(_back)
            .copyWith(previewSize: const Size(1080, 1920)),
      );
      expect(photoCamera.aspectRatio, closeTo(1080 / 1920, 1e-9));
    });

    testWidgets('shows the preview of the plugin', (tester) async {
      final photoCamera = camera();
      await photoCamera.initialize();
      when(() => controller.value)
          .thenReturn(const CameraValue.uninitialized(_back));
      await tester.pumpWidget(photoCamera.preview());
      expect(find.byType(CameraPreview), findsOneWidget);
    });

    test('takes a picture and deletes its file', () async {
      final directory = Directory.systemTemp.createTempSync('camera');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/p.jpg')..writeAsBytesSync([1, 2]);
      when(() => controller.takePicture())
          .thenAnswer((_) async => XFile(file.path));
      final photoCamera = camera();
      await photoCamera.initialize();
      expect(await photoCamera.takePicture(), [1, 2]);
      expect(file.existsSync(), isFalse);
    });

    test('ignores a file already gone, or in memory', () async {
      final directory = Directory.systemTemp.createTempSync('camera');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/gone.jpg')..writeAsBytesSync([3]);
      when(() => controller.takePicture()).thenAnswer((_) async {
        final bytes = file.readAsBytesSync();
        file.deleteSync();
        return XFile.fromData(bytes, path: file.path);
      });
      final photoCamera = camera();
      await photoCamera.initialize();
      expect(await photoCamera.takePicture(), [3]);
      when(() => controller.takePicture())
          .thenAnswer((_) async => XFile.fromData(Uint8List.fromList([4])));
      expect(await photoCamera.takePicture(), [4]);
    });

    test('disposes the controller', () async {
      await camera().dispose();
      final photoCamera = camera();
      await photoCamera.initialize();
      await photoCamera.dispose();
      verify(() => controller.dispose()).called(1);
    });

    test('uses the plugin by default', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'),
            (call) async => call.method == 'availableCameras'
                ? <Map<String, Object>>[]
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/camera'),
              null,
            ),
      );
      // The default controller of a camera, without opening it.
      final controller = PluginPhotoCamera.defaultController(_back);
      expect(controller.resolutionPreset, ResolutionPreset.veryHigh);
      expect(controller.enableAudio, isFalse);
      await expectLater(PluginPhotoCamera().initialize(), throwsA(anything));
    });
  });

  group(ImagePickerPhotoLibrary, () {
    late _MockImagePicker imagePicker;

    setUp(() {
      imagePicker = _MockImagePicker();
    });

    void stubMulti(Future<List<picker.XFile>> Function() answer) => when(
      () => imagePicker.pickMultiImage(
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) => answer());

    test('picks several reduced photos, at most the limit', () async {
      stubMulti(
        () async => [
          picker.XFile.fromData(Uint8List.fromList([1])),
          picker.XFile.fromData(Uint8List.fromList([2])),
          picker.XFile.fromData(Uint8List.fromList([3])),
        ],
      );
      final library = ImagePickerPhotoLibrary(imagePicker: imagePicker);
      expect(await library.pick(limit: 2), [
        [1],
        [2],
      ]);
      verify(
        () => imagePicker.pickMultiImage(
          maxWidth: ImagePickerPhotoLibrary.maxSide,
          maxHeight: ImagePickerPhotoLibrary.maxSide,
          imageQuality: ImagePickerPhotoLibrary.quality,
          limit: 2,
        ),
      ).called(1);
    });

    test('picks one photo when only one more fits', () async {
      final directory = Directory.systemTemp.createTempSync('library');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/one.jpg')..writeAsBytesSync([9]);
      when(
        () => imagePicker.pickImage(
          source: picker.ImageSource.gallery,
          maxWidth: any(named: 'maxWidth'),
          maxHeight: any(named: 'maxHeight'),
          imageQuality: any(named: 'imageQuality'),
        ),
      ).thenAnswer((_) async => picker.XFile(file.path));
      final library = ImagePickerPhotoLibrary(imagePicker: imagePicker);
      expect(await library.pick(limit: 1), [
        [9],
      ]);
      expect(file.existsSync(), isFalse);
    });

    test('a cancelled single pick gives nothing', () async {
      when(
        () => imagePicker.pickImage(
          source: picker.ImageSource.gallery,
          maxWidth: any(named: 'maxWidth'),
          maxHeight: any(named: 'maxHeight'),
          imageQuality: any(named: 'imageQuality'),
        ),
      ).thenAnswer((_) async => null);
      final library = ImagePickerPhotoLibrary(imagePicker: imagePicker);
      expect(await library.pick(limit: 1), isEmpty);
      expect(await library.pick(limit: 0), isEmpty);
    });

    test('ignores a temporary file already gone', () async {
      final directory = Directory.systemTemp.createTempSync('library');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/gone.jpg')..writeAsBytesSync([5]);
      stubMulti(() async {
        final bytes = file.readAsBytesSync();
        file.deleteSync();
        return [picker.XFile.fromData(bytes, path: file.path)];
      });
      final library = ImagePickerPhotoLibrary(imagePicker: imagePicker);
      expect(await library.pick(limit: 3), [
        [5],
      ]);
    });

    test('reports a refused access, rethrows other errors', () async {
      stubMulti(
        () async => throw PlatformException(code: 'photo_access_denied'),
      );
      final library = ImagePickerPhotoLibrary(imagePicker: imagePicker);
      await expectLater(
        library.pick(limit: 3),
        throwsA(isA<PhotoAccessDenied>()),
      );
      stubMulti(() async => throw PlatformException(code: 'other'));
      await expectLater(
        library.pick(limit: 3),
        throwsA(isA<PlatformException>()),
      );
    });

    test('uses image_picker by default', () {
      expect(ImagePickerPhotoLibrary(), isA<PhotoLibrary>());
    });
  });

  group('tilt', () {
    test('is 0 when the phone is upright, in portrait or landscape', () {
      expect(tiltDegrees(0, 9.8), closeTo(0, 1e-9));
      expect(tiltDegrees(9.8, 0), closeTo(0, 1e-9));
      expect(tiltDegrees(0, -9.8), closeTo(0, 1e-9));
      expect(tiltDegrees(-9.8, 0), closeTo(0, 1e-9));
    });

    test('is signed and at most 45°', () {
      expect(tiltDegrees(1.7, 9.6), closeTo(10.04, 0.01));
      expect(tiltDegrees(-1.7, 9.6), closeTo(-10.04, 0.01));
      expect(tiltDegrees(9.8, 9.8).abs(), closeTo(45, 1e-9));
    });

    test('comes from the accelerometer', () async {
      const channel = 'dev.fluttercommunity.plus/sensors/accelerometer';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
            (_) async => null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(channel),
            MockStreamHandler.inline(
              onListen: (_, events) => events.success(<double>[0, 9.8, 0, 0]),
            ),
          );
      expect(await accelerometerTilt().first, closeTo(0, 1e-9));
    });
  });
}
