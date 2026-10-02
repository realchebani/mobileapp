import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = ' ';

const _living = Room(
  id: 'r1',
  propertyId: 'property-id',
  name: 'Séjour',
  level: RoomLevel.groundFloor,
  areaM2: 30,
  isMain: true,
);

const _bedroom = Room(
  id: 'r2',
  propertyId: 'property-id',
  name: 'Chambre 1',
  level: RoomLevel.firstFloor,
  areaM2: 12,
  sortOrder: 1,
  isMain: true,
  photosCount: 2,
);

const _property = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
);

void main() {
  late MockPropertyRepository repository;

  setUpAll(() {
    registerFallbackValue(_living);
    registerFallbackValue(testRoomPhoto('fallback'));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.saveRoom(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as Room,
    );
    when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
    when(() => repository.deleteRoomPhotos(any())).thenAnswer((_) async {});
    when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
        .thenAnswer((_) async => []);
    when(() => repository.getPhotoUrls(any())).thenAnswer((_) async => {});
    when(() => repository.uploadRoomPhoto(any(), bytes: any(named: 'bytes')))
        .thenAnswer(
          (invocation) async =>
              invocation.positionalArguments.single as RoomPhoto,
        );
    when(() => repository.analyzeRoomPhoto(any())).thenAnswer(
      (_) async => const RoomPhotoAnalysis(floorCovering: 'carrelage'),
    );
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    List<Room> rooms = const [_living, _bedroom],
    Property property = _property,
    PhotoAnalysisConsent consent = PhotoAnalysisConsent.declined,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: property,
        rooms: rooms,
      ),
    );
    when(() => cubit.updateChildren(rooms: any(named: 'rooms')))
        .thenReturn(null);
    await tester.pumpTunnelPage(
      const SurfacesPage(),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
      photoServices: await testPhotoServices(
        consent: consent,
        library: FakePhotoLibrary(
          photos: [
            Uint8List.fromList([1]),
          ],
        ),
      ),
    );
    return cubit;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('SurfacesPage · photos (EPIC-15)', () {
    testWidgets('shows the photos and the main rooms still without one', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('Photos requises$_nbsp: 1/2'), findsOneWidget);
      expect(find.text('Photo requise'), findsOneWidget);
      expect(
        find.text(
          'Ajoutez au moins une photo de chaque pièce principale avant '
          'd’envoyer votre dossier.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Photos de Séjour$_nbsp: aucune'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Photos de Chambre 1$_nbsp: 2'),
        findsOneWidget,
      );
    });

    testWidgets('no requirement once every main room has a photo', (
      tester,
    ) async {
      await pump(tester, rooms: const [_bedroom]);
      expect(find.text('Photos requises$_nbsp: 1/1'), findsOneWidget);
      expect(find.text('Photo requise'), findsNothing);
    });

    testWidgets('a type without rooms requirement shows no indicator', (
      tester,
    ) async {
      await pump(
        tester,
        property: const Property(id: 'property-id', ownerId: 'user-id'),
        rooms: const [
          Room(
            id: 'r9',
            propertyId: 'property-id',
            name: 'Atelier',
            areaM2: 20,
            source: RoomSource.plan,
          ),
        ],
      );
      expect(find.textContaining('Photos requises'), findsNothing);
      expect(find.text('Extrait d’un document'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
    });

    testWidgets('the photos of a room: written first, counted back', (
      tester,
    ) async {
      final cubit = await pump(tester);
      await tap(
        tester,
        find.bySemanticsLabel('Photos de Séjour$_nbsp: aucune'),
      );
      expect(find.byType(RoomPhotosPage), findsOneWidget);
      // Stored and unchanged: not written again; recorded in the dossier.
      verifyNever(() => repository.saveRoom(any()));
      await tap(tester, find.text('Photothèque'));
      await tap(tester, find.text('Terminé'));
      expect(find.byType(RoomPhotosPage), findsNothing);
      expect(
        find.bySemanticsLabel('Photos de Séjour$_nbsp: 1'),
        findsOneWidget,
      );
      expect(find.text('Photo requise'), findsNothing);
      final rooms =
          verify(() => cubit.updateChildren(rooms: captureAny(named: 'rooms')))
                  .captured
                  .last
              as List<Room>;
      expect(rooms.first.photosCount, 1);
    });

    testWidgets('the suggestions applied come back to the room', (
      tester,
    ) async {
      when(() => repository.getRoomPhotos(any(), roomId: any(named: 'roomId')))
          .thenAnswer((_) async => [testRoomPhoto('a')]);
      await pump(tester, consent: PhotoAnalysisConsent.given);
      await tap(
        tester,
        find.bySemanticsLabel('Photos de Séjour$_nbsp: aucune'),
      );
      await tap(tester, find.text('Appliquer'));
      await tap(tester, find.text('Terminé'));
      expect(find.text('Carrelage'), findsOneWidget);
    });

    testWidgets('a room that cannot be written opens no photos', (
      tester,
    ) async {
      when(() => repository.saveRoom(any())).thenThrow(Exception());
      await pump(tester, rooms: const []);
      await tap(tester, find.text('Ajouter une pièce'));
      await tap(tester, find.text('Bureau'));
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(RealestyTextField, 'Surface'),
          matching: find.byType(TextField),
        ),
        '9',
      );
      await tap(tester, find.text('Photos de la pièce'));
      expect(find.byType(RoomPhotosPage), findsNothing);
      expect(
        find.text('La pièce n’a pas pu être enregistrée. Réessayez.'),
        findsOneWidget,
      );
      // The room is in the table anyway.
      expect(find.text('Bureau'), findsOneWidget);
    });

    testWidgets('a new room from the form, then its photos', (tester) async {
      final cubit = await pump(tester, rooms: const []);
      await tap(tester, find.text('Ajouter une pièce'));
      await tap(tester, find.text('Bureau'));
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(RealestyTextField, 'Surface'),
          matching: find.byType(TextField),
        ),
        '9',
      );
      await tap(tester, find.text('Photos de la pièce'));
      expect(find.byType(RoomPhotosPage), findsOneWidget);
      verify(() => repository.saveRoom(any())).called(1);
      final rooms =
          verify(() => cubit.updateChildren(rooms: captureAny(named: 'rooms')))
                  .captured
                  .single
              as List<Room>;
      expect(rooms.single.name, 'Bureau');
      await tap(tester, find.bySemanticsLabel('Retour aux pièces'));
      expect(
        find.bySemanticsLabel('Photos de Bureau$_nbsp: aucune'),
        findsOneWidget,
      );
    });

    testWidgets('the photos from the form of a room', (tester) async {
      await pump(tester);
      await tap(tester, find.bySemanticsLabel('Modifier Chambre 1'));
      expect(
        find.text('Les 2 photos de cette pièce seront supprimées avec elle.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Photos de la pièce (2)'));
      expect(find.byType(RoomPhotosPage), findsOneWidget);
      expect(find.text('Photos · Chambre 1'), findsOneWidget);
    });

    testWidgets('rooms all read on a plan: totals from a document', (
      tester,
    ) async {
      final cubit = await pump(
        tester,
        rooms: const [
          Room(
            id: 'r1',
            propertyId: 'property-id',
            name: 'Séjour',
            areaM2: 30,
            isMain: true,
            photosCount: 1,
            source: RoomSource.plan,
          ),
        ],
      );
      await tap(tester, find.text('C’est correct, continuer'));
      expect(savedStepPatch(cubit, SellerTunnelStep.surfaces), {
        PropertyColumns.livingAreaM2: 30.0,
        PropertyColumns.annexAreaM2: 0.0,
        PropertyColumns.provenance: {
          'living_area_m2': 'document',
          'annex_area_m2': 'declared',
        },
      });
    });
  });
}
