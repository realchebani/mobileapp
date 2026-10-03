import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/sale/listing/photos/listing_photos_page.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../../helpers/helpers.dart';
import '../../sale_helpers.dart';

ListingPhoto _photo(String id, {String? caption}) => ListingPhoto(
  id: id,
  saleId: 'sale-id',
  storagePath: 'user-id/sale-id/$id.jpg',
  caption: caption,
);

final _imported = Sale(
  id: 'sale-id',
  propertyId: 'property-id',
  formula: SaleFormula.essentiel,
  stage: SaleStage.mandateSigned,
  photosImportedAt: DateTime(2026, 10, 3),
);

void main() {
  setUpAll(() async {
    await loadRealestyFonts();
    registerFallbackValue(_photo('x'));
    registerFallbackValue(Uint8List(0));
  });

  late MockSaleRepository sales;
  late MockPropertyRepository properties;

  setUp(() {
    sales = MockSaleRepository();
    properties = MockPropertyRepository();
    when(() => sales.getListingPhotos('sale-id'))
        .thenAnswer((_) async => [_photo('a', caption: 'Séjour'), _photo('b')]);
    when(() => sales.listingPhotoUrls(any())).thenAnswer((_) async => {});
    when(() => sales.uploadListingPhoto(any(), bytes: any(named: 'bytes')))
        .thenAnswer(
          (invocation) async =>
              invocation.positionalArguments.first as ListingPhoto,
        );
    when(() => properties.getRooms(any())).thenAnswer((_) async => []);
    when(() => properties.getRoomPhotos(any())).thenAnswer((_) async => []);
    when(() => sales.updateSale(any(), any()))
        .thenAnswer((_) async => _imported);
  });

  Future<MockSaleCubit> pump(
    WidgetTester tester, {
    Sale? sale,
    PhotoLibrary? library,
  }) async {
    final cubit = mockSaleCubit(saleState(sale: sale ?? _imported));
    await tester.pumpSalePage(
      ListingPhotosPage(key: UniqueKey()),
      saleCubit: cubit,
      saleRepository: sales,
      propertyRepository: properties,
      photoServices: await testPhotoServices(
        camera: FakePhotoCamera(picture: Uint8List.fromList([1, 2])),
        library: library,
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  group(ListingPhotosPage, () {
    testWidgets('screenshot', (tester) async {
      usePhoneSurface();
      await pump(tester);
      expect(find.text('Couverture'), findsOneWidget);
      expect(find.text('Séjour'), findsOneWidget);
      expect(find.text('2 photos · minimum 5'), findsOneWidget);
      await tester.screenshot('listing_photos');
    });

    testWidgets('a new listing imports the dossier photos', (tester) async {
      usePhoneSurface();
      final cubit = await pump(tester, sale: testSale);
      verify(() => properties.getRoomPhotos('property-id')).called(1);
      verify(cubit.refresh).called(1);
    });

    testWidgets('cover and removal from the photo sheet', (tester) async {
      usePhoneSurface();
      when(
        () => sales.reorderListingPhotos('sale-id', ['b', 'a']),
      ).thenAnswer((_) async => [_photo('b'), _photo('a', caption: 'Séjour')]);
      when(() => sales.deleteListingPhoto(any())).thenThrow(Exception());
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mettre en couverture'));
      await tester.pumpAndSettle();
      verify(() => sales.reorderListingPhotos('sale-id', ['b', 'a'])).called(1);
      await tester.tap(find.bySemanticsLabel('Séjour'));
      await tester.pumpAndSettle();
      expect(find.text('Mettre en couverture'), findsOneWidget);
      await tester.tap(find.text('Retirer de l’annonce'));
      await tester.pumpAndSettle();
      expect(
        find.text('La modification n’a pas pu être enregistrée.'),
        findsOneWidget,
      );
      // Dismissed sheet: nothing happens.
      await tester.tap(find.bySemanticsLabel('Photo'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('camera photos are added', (tester) async {
      usePhoneSurface();
      await pump(tester);
      await tester.tap(find.text('Prendre des photos'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoCapturePage), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Prendre la photo'));
      await tester.pumpAndSettle();
      verify(() => sales.uploadListingPhoto(any(), bytes: any(named: 'bytes')))
          .called(1);
      await tester.tap(find.text('Terminé'));
      await tester.pumpAndSettle();
      expect(find.text('3 photos · minimum 5'), findsOneWidget);
    });

    testWidgets('library photos; a refused library is told', (tester) async {
      usePhoneSurface();
      await pump(
        tester,
        library: FakePhotoLibrary(
          photos: [
            Uint8List.fromList([3]),
          ],
        ),
      );
      await tester.tap(find.text('Choisir dans ma photothèque'));
      await tester.pumpAndSettle();
      expect(find.text('3 photos · minimum 5'), findsOneWidget);
      await pump(
        tester,
        library: FakePhotoLibrary(
          error: PlatformException(code: 'photo_access_denied'),
        ),
      );
      await tester.tap(find.text('Choisir dans ma photothèque'));
      await tester.pumpAndSettle();
      expect(
        find.text('La photothèque n’a pas pu être ouverte.'),
        findsOneWidget,
      );
    });

    testWidgets('notices: limit, failed copy; reimport', (tester) async {
      useTallSurface(4000);
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) async => [for (var i = 0; i < 40; i++) _photo('$i')]);
      await pump(tester);
      final take = tester.widget<RealestyButton>(
        find.widgetWithText(RealestyButton, 'Prendre des photos'),
      );
      expect(take.onPressed, isNull);
      when(() => sales.getListingPhotos('sale-id')).thenAnswer((_) async => []);
      when(() => properties.getRooms(any())).thenThrow(Exception());
      await pump(tester);
      expect(
        find.textContaining('Aucune photo pour l’instant'),
        findsOneWidget,
      );
      await tester.tap(find.text('Reprendre mes photos'));
      await tester.pumpAndSettle();
      expect(find.text('Une photo n’a pas pu être ajoutée.'), findsOneWidget);
    });

    testWidgets('loading; photos being added', (tester) async {
      usePhoneSurface();
      final gate = Completer<List<ListingPhoto>>();
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) => gate.future);
      final cubit = mockSaleCubit(saleState(sale: _imported));
      final upload = Completer<ListingPhoto>();
      when(() => sales.uploadListingPhoto(any(), bytes: any(named: 'bytes')))
          .thenAnswer((_) => upload.future);
      await tester.pumpSalePage(
        ListingPhotosPage(key: UniqueKey()),
        saleCubit: cubit,
        saleRepository: sales,
        propertyRepository: properties,
        photoServices: await testPhotoServices(
          library: FakePhotoLibrary(
            photos: [
              Uint8List.fromList([3]),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete([]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir dans ma photothèque'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      upload.complete(_photo('n'));
      await tester.pumpAndSettle();
    });

    testWidgets('while the dossier photos are copied', (tester) async {
      usePhoneSurface();
      when(() => sales.getListingPhotos('sale-id')).thenAnswer((_) async => []);
      when(() => properties.getRoomPhotos(any())).thenAnswer(
        (_) async => const [
          RoomPhoto(
            id: 'rp',
            propertyId: 'property-id',
            roomId: 'r',
            storagePath: 'user-id/property-id/photos/r/rp.jpg',
          ),
        ],
      );
      final copy = Completer<ListingPhoto>();
      when(
        () => sales.copyRoomPhoto(any(), sourcePath: any(named: 'sourcePath')),
      ).thenAnswer((_) => copy.future);
      await tester.pumpSalePage(
        ListingPhotosPage(key: UniqueKey()),
        saleCubit: mockSaleCubit(saleState()),
        saleRepository: sales,
        propertyRepository: properties,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Copie des photos de votre dossier…'), findsOneWidget);
      copy.complete(_photo('c'));
      await tester.pumpAndSettle();
    });

    testWidgets('loading, failure', (tester) async {
      usePhoneSurface();
      when(() => sales.getListingPhotos('sale-id')).thenThrow(Exception());
      await pump(tester);
      expect(find.text('Impossible de charger les photos.'), findsOneWidget);
    });
  });
}
