import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';

void main() {
  group(PhotoPreferences, () {
    test('remembers the consent, given or declined', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PhotoPreferences(
        preferences: await SharedPreferences.getInstance(),
      );
      expect(preferences.consent, PhotoAnalysisConsent.unknown);
      await preferences.setConsent(given: false);
      expect(preferences.consent, PhotoAnalysisConsent.declined);
      await preferences.setConsent(given: true);
      expect(preferences.consent, PhotoAnalysisConsent.given);
    });
  });

  group(PhotoServices, () {
    test('defaults to the device and no vision AI', () {
      const services = PhotoServices();
      expect(services.analysisAvailable, isFalse);
      expect(services.analysisAccepted, isFalse);
      expect(services.newCamera(), isA<PluginPhotoCamera>());
      expect(services.photoLibrary, isA<ImagePickerPhotoLibrary>());
      expect(services.photoProcessor, isA<IsolatePhotoProcessor>());
      expect(services.tiltStream, accelerometerTilt);
    });

    test('uses what it is given', () async {
      final camera = FakePhotoCamera();
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.given,
        camera: camera,
      );
      expect(services.analysisAvailable, isTrue);
      expect(services.analysisAccepted, isTrue);
      expect(services.newCamera(), camera);
      expect(services.photoLibrary, isA<FakePhotoLibrary>());
      expect(services.photoProcessor, isA<FakePhotoProcessor>());
    });

    testWidgets('of reads the provided services, or the defaults', (
      tester,
    ) async {
      final services = await testPhotoServices();
      late PhotoServices found;
      late PhotoServices fallback;
      await tester.pumpWidget(
        Column(
          children: [
            Builder(
              builder: (context) {
                fallback = PhotoServices.of(context);
                return const SizedBox();
              },
            ),
            RepositoryProvider.value(
              value: services,
              child: Builder(
                builder: (context) {
                  found = PhotoServices.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      );
      expect(found, services);
      expect(fallback.analysisAvailable, isFalse);
    });
  });
}
