import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_cards.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_tile.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = ' ';

const _living = RoomInput(
  name: 'Séjour',
  level: RoomLevel.groundFloor,
  areaM2: 30,
  floorCovering: 'parquet',
  isMain: true,
);

void main() {
  late MockPropertyRepository repository;
  late List<RoomPhoto> stored;

  setUpAll(() {
    registerFallbackValue(testRoomPhoto('fallback'));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    stored = [];
    repository = MockPropertyRepository();
    when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
        .thenAnswer((_) async => stored);
    when(() => repository.getPhotoUrls(any())).thenAnswer(
      (invocation) async => {
        for (final path in invocation.positionalArguments.single as List)
          path as String: 'https://x/$path',
      },
    );
    when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
        .thenAnswer(
          (invocation) async =>
              invocation.positionalArguments.single as RoomPhoto,
        );
    when(() => repository.analyzeRoomPhoto(any())).thenAnswer(
      (_) async => const RoomPhotoAnalysis(
        roomKind: 'kitchen',
        floorCovering: 'carrelage',
        glazing: Glazing.double,
        conditionNotes: ['Joints noircis'],
        personalItems: ['Courrier'],
        peopleVisible: true,
      ),
    );
    when(() => repository.deleteRoomPhoto(any())).thenAnswer((_) async {});
    when(() => repository.discardRoomPhoto(any())).thenAnswer((_) async {});
    when(() => repository.reorderRoomPhotos(any())).thenAnswer(
      (invocation) async => [
        for (final (i, p)
            in (invocation.positionalArguments.single as List<RoomPhoto>)
                .indexed)
          p.withSortOrder(i),
      ],
    );
  });

  /// Pumps a button opening the photos of the living room; returns what
  /// the screen hands back once closed.
  Future<List<RoomPhotosResult?>> pump(
    WidgetTester tester, {
    PhotoServices? services,
    RoomInput room = _living,
    bool readOnly = false,
    bool settle = true,
  }) async {
    usePhoneSurface();
    final results = <RoomPhotosResult?>[];
    final photoServices = services ?? await testPhotoServices();
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await showRoomPhotos(
              context,
              ownerId: 'user-id',
              propertyId: 'property-id',
              roomId: 'r1',
              room: room,
              otherNames: const ['Chambre 1'],
              readOnly: readOnly,
            ),
          ),
          child: const Text('go'),
        ),
      ),
      propertyRepository: repository,
      photoServices: photoServices,
    );
    await tester.tap(find.text('go'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // Spinners never settle: let the route open.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    return results;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group(RoomPhotosPage, () {
    testWidgets('a main room without photos', (tester) async {
      final results = await pump(tester);
      expect(find.text('Photos · Séjour'), findsOneWidget);
      expect(find.text('Aucune photo'), findsOneWidget);
      expect(
        find.text(
          'Séjour est une pièce principale$_nbsp: ajoutez au moins une photo '
          'pour pouvoir envoyer votre dossier. Montrez la pièce entière, et '
          'ses défauts éventuels.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pour de bonnes photos'), findsOneWidget);
      expect(
        find.text('Personne dans le champ, ni dans les miroirs.'),
        findsOneWidget,
      );
      expect(find.text('Aucune photo pour l’instant.'), findsOneWidget);
      // No photo: no suggestion, no "activate".
      expect(find.text('Suggestions de l’IA'), findsNothing);
      expect(find.text('Activer les suggestions de l’IA'), findsNothing);

      await tap(tester, find.text('Terminé'));
      expect(results, [const RoomPhotosResult(photosCount: 0)]);
    });

    testWidgets('another room has a lighter intro', (tester) async {
      await pump(
        tester,
        room: const RoomInput(name: 'Cellier', level: null, areaM2: 4),
      );
      expect(
        find.textContaining('Des photos de Cellier aident l’expert'),
        findsOneWidget,
      );
    });

    testWidgets('a failed load can be retried', (tester) async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenThrow(Exception());
      await pump(tester);
      expect(
        find.text('Les photos n’ont pas pu être chargées.'),
        findsOneWidget,
      );
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => []);
      await tap(tester, find.text('Réessayer'));
      expect(find.text('Aucune photo pour l’instant.'), findsOneWidget);
    });

    testWidgets('the library: consent asked first, then the photos sent', (
      tester,
    ) async {
      final library = FakePhotoLibrary(
        photos: [
          Uint8List.fromList([1]),
          Uint8List.fromList([2]),
        ],
      );
      final services = await testPhotoServices(library: library);
      final results = await pump(tester, services: services);
      await tap(tester, find.text('Photothèque'));
      expect(find.byType(PhotoConsentPage), findsOneWidget);
      await tap(tester, find.text('Continuer sans l’IA'));
      expect(library.limits, [12]);
      expect(find.byType(PhotoTile), findsNWidgets(2));
      expect(find.text('Principale'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('2 sur 12'), findsOneWidget);
      verifyNever(() => repository.analyzeRoomPhoto(any()));
      // Declined: the vision AI can still be turned on.
      expect(find.text('Activer les suggestions de l’IA'), findsOneWidget);

      await tap(tester, find.text('Terminé'));
      expect(results.single?.photosCount, 2);
      expect(results.single?.room, isNull);
    });

    testWidgets('tells when the library is refused or fails', (tester) async {
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
        library: FakePhotoLibrary(error: const PhotoAccessDenied('x')),
      );
      await pump(tester, services: services);
      await tap(tester, find.text('Photothèque'));
      expect(
        find.text(
          'Accès refusé$_nbsp: autorisez l’appareil photo ou les photos dans '
          'les Réglages.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tells when the library cannot open', (tester) async {
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
        library: FakePhotoLibrary(error: PlatformException(code: 'x')),
      );
      await pump(tester, services: services);
      await tap(tester, find.text('Photothèque'));
      expect(find.text('La photothèque n’a pas pu s’ouvrir.'), findsOneWidget);
    });

    testWidgets('the camera keeps its photos, analysed once accepted', (
      tester,
    ) async {
      final camera = FakePhotoCamera();
      final services = await testPhotoServices(camera: camera);
      await pump(tester, services: services);
      await tap(tester, find.text('Photographier'));
      await tap(tester, find.text('J’accepte l’analyse'));
      expect(find.byType(PhotoCapturePage), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Prendre la photo'));
      await tap(tester, find.text('Terminé'));
      expect(find.byType(PhotoCapturePage), findsNothing);
      expect(find.byType(PhotoTile), findsOneWidget);
      verify(() => repository.analyzeRoomPhoto(any())).called(1);
      // The suggestions of the analysis.
      expect(find.text('Suggestions de l’IA'), findsOneWidget);
      expect(find.text('Type de pièce$_nbsp: Cuisine'), findsOneWidget);
      expect(find.text('Revêtement$_nbsp: Carrelage'), findsOneWidget);
      expect(find.text('Vitrage$_nbsp: Double'), findsOneWidget);
      expect(find.text('Joints noircis'), findsOneWidget);
      expect(
        find.text(
          'Une personne est visible sur 1 photo$_nbsp: reprenez-la ou '
          'supprimez-la.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('À ranger avant les photos de l’annonce$_nbsp: Courrier'),
        findsOneWidget,
      );
      expect(find.text('Personne visible'), findsOneWidget);
    });

    testWidgets('applied suggestions come back with the room', (tester) async {
      stored = [
        testRoomPhoto(
          'a',
          analysis: const RoomPhotoAnalysis(
            roomKind: 'bedroom',
            floorCovering: 'carrelage',
            glazing: Glazing.double,
            conditionNotes: ['Joints noircis'],
          ),
        ),
      ];
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.given,
      );
      final results = await pump(tester, services: services);
      for (var i = 0; i < 4; i++) {
        final button = find
            .descendant(
              of: find.byType(PhotoSuggestionsCard),
              matching: find.byType(RealestyButton),
            )
            .first;
        await tap(tester, button);
      }
      expect(find.textContaining('4 suggestions appliquées'), findsOneWidget);
      expect(
        find.text(
          'Rien à changer$_nbsp: vos réponses correspondent aux photos.',
        ),
        findsOneWidget,
      );
      expect(find.text('Photos · Chambre 2'), findsOneWidget);
      await tap(tester, find.text('Terminé'));
      expect(
        results.single,
        const RoomPhotosResult(
          photosCount: 1,
          room: RoomInput(
            name: 'Chambre 2',
            level: RoomLevel.groundFloor,
            areaM2: 30,
            floorCovering: 'carrelage',
            glazing: Glazing.double,
            isMain: true,
            description: 'Joints noircis',
          ),
        ),
      );
    });

    testWidgets('turns the vision AI on after a refusal', (tester) async {
      stored = [testRoomPhoto('a')];
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
      );
      await pump(tester, services: services);
      await tap(tester, find.text('Activer les suggestions de l’IA'));
      await tap(tester, find.text('J’accepte l’analyse'));
      expect(find.text('Suggestions de l’IA'), findsOneWidget);
      verify(() => repository.analyzeRoomPhoto('a')).called(1);
    });

    testWidgets('a refusal from "activate" keeps the photos as they are', (
      tester,
    ) async {
      stored = [testRoomPhoto('a')];
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
      );
      await pump(tester, services: services);
      await tap(tester, find.text('Activer les suggestions de l’IA'));
      await tap(tester, find.text('Continuer sans l’IA'));
      expect(find.text('Suggestions de l’IA'), findsNothing);
    });

    testWidgets('shows the analysis in progress and its failures', (
      tester,
    ) async {
      stored = [testRoomPhoto('a')];
      final gate = Completer<RoomPhotoAnalysis>();
      when(() => repository.analyzeRoomPhoto(any()))
          .thenAnswer((_) => gate.future);
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.given,
      );
      await pump(tester, services: services, settle: false);
      expect(find.text('L’IA regarde votre photo…'), findsOneWidget);
      gate.completeError(Exception());
      await tester.pumpAndSettle();
      expect(find.text('1 photo n’a pas pu être analysée.'), findsOneWidget);
      when(() => repository.analyzeRoomPhoto(any())).thenAnswer(
        (_) async => const RoomPhotoAnalysis(roomKind: 'livingRoom'),
      );
      await tap(
        tester,
        find.descendant(
          of: find.byType(PhotoSuggestionsCard),
          matching: find.text('Réessayer'),
        ),
      );
      expect(find.text('1 photo n’a pas pu être analysée.'), findsNothing);
    });

    testWidgets('tells when the analysis quota is reached', (tester) async {
      stored = [testRoomPhoto('a')];
      when(() => repository.analyzeRoomPhoto(any()))
          .thenThrow(const VisionQuotaFailure('x'));
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.given,
      );
      await pump(tester, services: services);
      expect(
        find.text(
          'Limite d’analyses du jour atteinte$_nbsp: réessayez demain.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the detail of a photo: put first, delete', (tester) async {
      stored = [
        testRoomPhoto('a'),
        testRoomPhoto(
          'b',
          sortOrder: 1,
          quality: const PhotoQuality(issues: [PhotoQualityIssue.dark]),
          analysis: const RoomPhotoAnalysis(
            conditionNotes: ['Fissure'],
            personalItems: ['Courrier'],
            peopleVisible: true,
          ),
        ),
      ];
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
      );
      await pump(tester, services: services);
      expect(find.text('Sombre'), findsOneWidget);
      await tap(tester, find.byType(PhotoTile).last);
      expect(find.text('Photo 2 sur 2'), findsOneWidget);
      expect(find.text('À vérifier$_nbsp: sombre.'), findsOneWidget);
      expect(
        find.text(
          '• Une personne est visible$_nbsp: reprenez ou supprimez '
          'cette photo.',
        ),
        findsOneWidget,
      );
      expect(find.text('• Fissure'), findsOneWidget);
      await tap(tester, find.text('Mettre en premier'));
      verify(() => repository.reorderRoomPhotos(any())).called(1);

      await tap(tester, find.byType(PhotoTile).first);
      expect(find.text('Photo 1 sur 2'), findsOneWidget);
      expect(find.text('Mettre en premier'), findsNothing);
      await tap(tester, find.text('Supprimer la photo'));
      verify(() => repository.deleteRoomPhoto(any())).called(1);
      expect(find.byType(PhotoTile), findsOneWidget);

      await tap(tester, find.byType(PhotoTile).first);
      expect(find.text('Aucun défaut détecté.'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Fermer'));
      expect(find.byType(PhotoTile), findsOneWidget);
    });

    testWidgets('the last photo of a main room of a sent dossier stays', (
      tester,
    ) async {
      stored = [testRoomPhoto('a')];
      when(() => repository.deleteRoomPhoto(any()))
          .thenThrow(const RoomPhotoRequiredFailure('x'));
      await pump(tester);
      await tap(tester, find.byType(PhotoTile).first);
      await tap(tester, find.text('Supprimer la photo'));
      expect(find.byType(PhotoTile), findsOneWidget);
      expect(
        find.text(
          'Cette pièce principale doit garder au moins une photo : '
                  'ajoutez-en une autre avant de supprimer celle-ci.'
              .replaceAll(' :', '$_nbsp:'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed upload can be retried or removed', (tester) async {
      when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
          .thenThrow(const DocumentUploadFailure('x'));
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
        library: FakePhotoLibrary(
          photos: [
            Uint8List.fromList([1]),
            Uint8List.fromList([2]),
          ],
        ),
      );
      await pump(tester, services: services);
      await tap(tester, find.text('Photothèque'));
      expect(find.text('Échec de l’envoi'), findsNWidgets(2));
      expect(
        find.text('Une photo n’a pas pu être envoyée. Réessayez.'),
        findsOneWidget,
      );
      await tap(tester, find.bySemanticsLabel('Retirer').first);
      expect(find.text('Échec de l’envoi'), findsOneWidget);
      when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
          .thenAnswer(
            (invocation) async =>
                invocation.positionalArguments.single as RoomPhoto,
          );
      await tap(tester, find.bySemanticsLabel('Réessayer'));
      expect(find.text('Échec de l’envoi'), findsNothing);
      expect(find.byType(PhotoTile), findsOneWidget);
    });

    testWidgets('shows the photos being sent; back waits', (tester) async {
      final gate = Completer<void>();
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
        library: FakePhotoLibrary(
          photos: [
            Uint8List.fromList([1]),
          ],
        ),
        processor: FakePhotoProcessor(gate: gate),
      );
      await pump(tester, services: services);
      await tester.ensureVisible(find.text('Photothèque'));
      await tester.tap(find.text('Photothèque'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Envoi en cours'), findsOneWidget);
      expect(find.text('Envoi de vos photos…'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Retour aux pièces'));
      await tester.pump();
      expect(find.byType(RoomPhotosPage), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      await tap(tester, find.bySemanticsLabel('Retour aux pièces'));
      expect(find.byType(RoomPhotosPage), findsNothing);
    });

    testWidgets('the vision AI can be turned off', (tester) async {
      stored = [testRoomPhoto('a')];
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.given,
      );
      await pump(tester, services: services);
      await tap(tester, find.text('Désactiver les suggestions de l’IA'));
      expect(services.preferences!.consent, PhotoAnalysisConsent.declined);
      expect(find.text('Suggestions de l’IA'), findsNothing);
      expect(find.text('Activer les suggestions de l’IA'), findsOneWidget);
    });

    testWidgets('the system back closes like the back button', (tester) async {
      final results = await pump(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RoomPhotosPage), findsNothing);
      expect(results, [const RoomPhotosResult(photosCount: 0)]);
    });

    testWidgets('large text stacks the photo buttons', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      expect(
        tester.getTopLeft(find.text('Photothèque')).dy,
        greaterThan(tester.getTopLeft(find.text('Photographier')).dy),
      );
    });

    testWidgets('the limit of 12 photos disables the buttons', (tester) async {
      stored = [for (var i = 0; i < 12; i++) testRoomPhoto('$i', sortOrder: i)];
      await pump(tester);
      expect(
        tester
            .widget<RealestyButton>(
              find.widgetWithText(RealestyButton, 'Photographier'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('12 sur 12'), findsOneWidget);
    });

    testWidgets('read only: no button, no action on a photo', (tester) async {
      stored = [testRoomPhoto('a'), testRoomPhoto('b', sortOrder: 1)];
      await pump(tester, readOnly: true);
      expect(find.text('Photographier'), findsNothing);
      expect(find.text('Pour de bonnes photos'), findsNothing);
      await tap(tester, find.byType(PhotoTile).last);
      expect(find.text('Mettre en premier'), findsNothing);
      expect(find.text('Supprimer la photo'), findsNothing);
    });
  });
}
