import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

class _MockRoomPhotosCubit extends MockCubit<RoomPhotosState>
    implements RoomPhotosCubit;

const _nbsp = ' ';

void main() {
  late _MockRoomPhotosCubit cubit;
  late FakePhotoCamera camera;
  late FakePhotoProcessor processor;
  late StreamController<double> tilt;
  late List<Uri> opened;

  setUpAll(() => registerFallbackValue(processedPhoto()));

  setUp(() {
    cubit = _MockRoomPhotosCubit();
    when(() => cubit.state)
        .thenReturn(const RoomPhotosState(status: RoomPhotosStatus.ready));
    camera = FakePhotoCamera();
    processor = FakePhotoProcessor();
    tilt = StreamController<double>.broadcast(sync: true);
    opened = [];
  });

  tearDown(() => tilt.close());

  Future<void> pump(WidgetTester tester) async {
    usePhoneSurface();
    await tester.pumpApp(
      BlocProvider<RoomPhotosCubit>.value(
        value: cubit,
        child: PhotoCapturePage(
          camera: camera,
          processor: processor,
          tilt: () => tilt.stream,
          openUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder shutter() => find.bySemanticsLabel('Prendre la photo');

  group(PhotoCapturePage, () {
    testWidgets('shows the preview, the instruction and the grid', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.text('Personne dans le champ · Allumez et ouvrez les rideaux'),
        findsOneWidget,
      );
      expect(find.byType(ColoredBox), findsWidgets);
      expect(find.text('Aucune photo prise'), findsOneWidget);
      expect(find.text('Redressez le téléphone'), findsNothing);
    });

    testWidgets('a level photo is kept at once', (tester) async {
      await pump(tester);
      tilt.add(1.5);
      await tester.pump();
      expect(find.bySemanticsLabel('Téléphone droit'), findsOneWidget);
      await tester.tap(shutter());
      await tester.pumpAndSettle();
      verify(() => cubit.addFromCamera(any())).called(1);
      expect(processor.tilts, [1.5]);
      expect(find.text('1 photo prise'), findsOneWidget);
    });

    testWidgets('shows a spinner while the photo is checked', (tester) async {
      final gate = Completer<void>();
      processor = FakePhotoProcessor(gate: gate);
      await pump(tester);
      await tester.tap(shutter());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // A second tap is ignored while busy.
      await tester.tap(shutter());
      gate.complete();
      await tester.pumpAndSettle();
      expect(camera.taken, 1);
      verify(() => cubit.addFromCamera(any())).called(1);
    });

    testWidgets('shows when the phone is tilted', (tester) async {
      await pump(tester);
      tilt
        ..add(12)
        ..addError(Exception());
      await tester.pump();
      expect(find.text('Redressez le téléphone'), findsOneWidget);
    });

    testWidgets('a photo with defects: retake or keep', (tester) async {
      processor = FakePhotoProcessor(
        issues: const [PhotoQualityIssue.dark, PhotoQualityIssue.blurry],
      );
      await pump(tester);
      await tester.tap(shutter());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Photo à vérifier$_nbsp: sombre, floue. Reprenez-la si possible.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Reprendre'));
      await tester.pumpAndSettle();
      verifyNever(() => cubit.addFromCamera(any()));
      await tester.tap(shutter());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garder'));
      await tester.pumpAndSettle();
      verify(() => cubit.addFromCamera(any())).called(1);
      expect(find.text('1 photo prise'), findsOneWidget);
    });

    testWidgets('tells when the photo could not be taken', (tester) async {
      camera = FakePhotoCamera(takeError: Exception());
      await pump(tester);
      await tester.tap(shutter());
      await tester.pumpAndSettle();
      expect(
        find.text('La photo n’a pas pu être prise. Réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('a refused camera opens the settings', (tester) async {
      camera = FakePhotoCamera(
        initializeError: const PhotoAccessDenied('denied'),
      );
      await pump(tester);
      expect(
        find.text(
          'Autorisez l’appareil photo dans les Réglages pour photographier '
          'vos pièces.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Ouvrir les Réglages'));
      expect(opened, [Uri.parse('app-settings:')]);
    });

    testWidgets('an unavailable camera points to the library', (tester) async {
      camera = FakePhotoCamera(initializeError: Exception());
      await pump(tester);
      expect(
        find.text(
          'L’appareil photo n’est pas disponible. Utilisez la photothèque.',
        ),
        findsOneWidget,
      );
      await tester.tap(shutter());
      await tester.pumpAndSettle();
      expect(camera.taken, 0);
    });

    testWidgets('no more photo once the room is full', (tester) async {
      when(() => cubit.state).thenReturn(
        RoomPhotosState(
          status: RoomPhotosStatus.ready,
          photos: [for (var i = 0; i < 12; i++) testRoomPhoto('$i')],
        ),
      );
      await pump(tester);
      await tester.tap(shutter());
      await tester.pumpAndSettle();
      expect(camera.taken, 0);
    });

    testWidgets('"Terminé" and the close button leave', (tester) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPhotoCapture(
              context,
              cubit: cubit,
              camera: camera,
              processor: processor,
              tilt: () => tilt.stream,
            ),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoCapturePage), findsOneWidget);
      await tester.tap(find.text('Terminé'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoCapturePage), findsNothing);
      expect(camera.disposed, isTrue);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Fermer l’appareil photo'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoCapturePage), findsNothing);
    });
  });
}
