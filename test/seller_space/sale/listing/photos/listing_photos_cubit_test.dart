import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/sale/listing/photos/listing_photos_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../../helpers/helpers.dart';
import '../../../fixtures.dart';
import '../../sale_helpers.dart';

void main() {
  late MockSaleRepository sales;
  late MockPropertyRepository properties;
  late int ids;

  ListingPhoto photo(String id, {String? source, int order = 0}) =>
      ListingPhoto(
        id: id,
        saleId: 'sale-id',
        storagePath: 'user-id/sale-id/$id.jpg',
        sourceRoomPhotoId: source,
        sortOrder: order,
      );

  RoomPhoto roomPhoto(String id, String room, int order) => RoomPhoto(
    id: id,
    propertyId: 'property-id',
    roomId: room,
    storagePath: 'user-id/property-id/photos/$room/$id.jpg',
    sortOrder: order,
  );

  setUpAll(() {
    registerFallbackValue(photo('x'));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    ids = 0;
    sales = MockSaleRepository();
    properties = MockPropertyRepository();
    when(() => sales.getListingPhotos('sale-id')).thenAnswer((_) async => []);
    when(() => sales.listingPhotoUrls(any())).thenAnswer(
      (invocation) async => {
        for (final path in invocation.positionalArguments.first as List<String>)
          path: 'https://$path',
      },
    );
    when(() => sales.updateSale('sale-id', any()))
        .thenAnswer((_) async => testSale);
    when(() => properties.getRooms('property-id')).thenAnswer(
      (_) async => const [
        Room(
          id: 'r2',
          propertyId: 'property-id',
          name: 'Cuisine',
          sortOrder: 1,
          areaM2: 10,
        ),
        Room(id: 'r1', propertyId: 'property-id', name: 'Séjour', areaM2: 30),
        Room(propertyId: 'property-id', name: 'Sans id', areaM2: 5),
      ],
    );
    when(() => properties.getRoomPhotos('property-id')).thenAnswer(
      (_) async => [
        roomPhoto('k1', 'r2', 0),
        roomPhoto('s2', 'r1', 1),
        roomPhoto('s1', 'r1', 0),
        roomPhoto('x', 'unknown', 0),
      ],
    );
    when(() => sales.copyRoomPhoto(any(), sourcePath: any(named: 'sourcePath')))
        .thenAnswer(
          (invocation) async =>
              invocation.positionalArguments.first as ListingPhoto,
        );
    when(() => sales.uploadListingPhoto(any(), bytes: any(named: 'bytes')))
        .thenAnswer(
          (invocation) async =>
              invocation.positionalArguments.first as ListingPhoto,
        );
  });

  ListingPhotosCubit build({
    Sale sale = testSale,
    void Function()? onImported,
  }) => ListingPhotosCubit(
    saleRepository: sales,
    propertyRepository: properties,
    processor: FakePhotoProcessor(),
    sale: sale,
    ownerId: 'user-id',
    members: const [certifiedProperty],
    onImported: onImported,
    generateId: () => 'p${ids++}',
  );

  group(ListingPhotosCubit, () {
    test('the first load copies every dossier photo, room by room', () async {
      var imported = 0;
      final cubit = build(onImported: () => imported++);
      await cubit.load();
      expect(cubit.state.status, ListingPhotosStatus.ready);
      expect(
        [for (final p in cubit.state.photos) p.sourceRoomPhotoId],
        ['s1', 's2', 'k1', 'x'],
      );
      expect(cubit.state.photos.first.caption, 'Séjour');
      expect(cubit.state.photos.last.caption, isNull);
      expect(cubit.state.urls, hasLength(4));
      expect(cubit.state.importing, isFalse);
      expect(imported, 1);
      verify(
        () => sales.copyRoomPhoto(
          any(),
          sourcePath: 'user-id/property-id/photos/r1/s1.jpg',
        ),
      ).called(1);
      verify(() => sales.updateSale('sale-id', any())).called(1);
      // A second import copies nothing new.
      clearInteractions(sales);
      await cubit.importDossierPhotos();
      verifyNever(
        () => sales.copyRoomPhoto(any(), sourcePath: any(named: 'sourcePath')),
      );
      await cubit.close();
    });

    test('an imported sale only loads; a failed copy is told', () async {
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) async => [photo('a', source: 's1')]);
      final imported = Sale(
        id: 'sale-id',
        formula: SaleFormula.essentiel,
        stage: SaleStage.mandateSigned,
        photosImportedAt: DateTime(2026),
      );
      final cubit = build(sale: imported);
      await cubit.load();
      expect(cubit.state.photos, hasLength(1));
      verifyNever(() => properties.getRooms(any()));
      when(
        () => sales.copyRoomPhoto(any(), sourcePath: any(named: 'sourcePath')),
      ).thenThrow(Exception());
      await cubit.importDossierPhotos();
      expect(cubit.state.notice, ListingPhotosNotice.addFailed);
      expect(cubit.state.noticeCount, 1);
      verifyNever(() => sales.updateSale(any(), any()));
      when(() => properties.getRooms('property-id')).thenThrow(Exception());
      await cubit.importDossierPhotos();
      expect(cubit.state.noticeCount, 2);
      await cubit.close();
    });

    test('load failure; URL failure', () async {
      when(() => sales.getListingPhotos('sale-id')).thenThrow(Exception());
      var cubit = build();
      await cubit.load();
      expect(cubit.state.status, ListingPhotosStatus.failure);
      expect(cubit.canAddPhoto, isFalse);
      await cubit.close();
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) async => [photo('a')]);
      when(() => sales.listingPhotoUrls(any())).thenThrow(Exception());
      cubit = build(
        sale: Sale(
          id: 'sale-id',
          formula: SaleFormula.essentiel,
          stage: SaleStage.mandateSigned,
          photosImportedAt: DateTime(2026),
        ),
      );
      await cubit.load();
      expect(cubit.state.urls, isEmpty);
      await cubit.close();
    });

    test('camera and library photos are uploaded in order', () async {
      final imported = Sale(
        id: 'sale-id',
        formula: SaleFormula.essentiel,
        stage: SaleStage.mandateSigned,
        photosImportedAt: DateTime(2026),
      );
      final cubit = build(sale: imported);
      await cubit.load();
      expect(cubit.canAddPhoto, isTrue);
      cubit
        ..addFromCamera(processedPhoto())
        ..addFromLibrary([
          Uint8List.fromList([4, 5]),
        ]);
      expect(cubit.state.adding, 2);
      await Future<void>.delayed(Duration.zero);
      await pumpEventQueue();
      expect(cubit.state.adding, 0);
      expect(cubit.state.photos, hasLength(2));
      expect(cubit.state.photos.last.sortOrder, 1);
      expect(cubit.state.photos.first.propertyId, 'property-id');
      when(() => sales.uploadListingPhoto(any(), bytes: any(named: 'bytes')))
          .thenThrow(const SaleFailure(SaleFailureReason.photoLimitReached));
      cubit.addFromCamera(processedPhoto());
      await pumpEventQueue();
      expect(cubit.state.notice, ListingPhotosNotice.limitReached);
      when(() => sales.uploadListingPhoto(any(), bytes: any(named: 'bytes')))
          .thenThrow(Exception());
      cubit.addFromCamera(processedPhoto());
      await pumpEventQueue();
      expect(cubit.state.notice, ListingPhotosNotice.addFailed);
      await cubit.close();
      cubit.addFromCamera(processedPhoto());
    });

    test('40 photos at most', () async {
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) async => [for (var i = 0; i < 40; i++) photo('$i')]);
      final cubit = build();
      await cubit.load();
      verifyNever(
        () => sales.copyRoomPhoto(any(), sourcePath: any(named: 'sourcePath')),
      );
      cubit.addFromLibrary([Uint8List(1)]);
      expect(cubit.state.notice, ListingPhotosNotice.limitReached);
      await cubit.close();
    });

    test('remove and make cover', () async {
      final a = photo('a');
      final b = photo('b', order: 1);
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) async => [a, b]);
      when(() => sales.deleteListingPhoto(a)).thenAnswer((_) async {});
      when(() => sales.reorderListingPhotos('sale-id', ['b', 'a']))
          .thenAnswer((_) async => [b, a]);
      final cubit = build(
        sale: Sale(
          id: 'sale-id',
          formula: SaleFormula.essentiel,
          stage: SaleStage.mandateSigned,
          photosImportedAt: DateTime(2026),
        ),
      );
      await cubit.load();
      await cubit.makeCover(b);
      expect(cubit.state.photos, [b, a]);
      await cubit.remove(a);
      expect(cubit.state.photos, [b]);
      when(() => sales.deleteListingPhoto(b)).thenThrow(Exception());
      await cubit.remove(b);
      expect(cubit.state.notice, ListingPhotosNotice.changeFailed);
      // A change in progress ignores another one.
      final gate = Completer<void>();
      when(() => sales.deleteListingPhoto(b)).thenAnswer((_) => gate.future);
      final first = cubit.remove(b);
      await cubit.remove(b);
      gate.complete();
      await first;
      await cubit.close();
    });

    test('a closed cubit ignores late answers', () async {
      final gate = Completer<List<ListingPhoto>>();
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) => gate.future);
      var cubit = build();
      var load = cubit.load();
      await cubit.close();
      gate.complete([]);
      await load;
      final failing = Completer<List<ListingPhoto>>();
      when(() => sales.getListingPhotos('sale-id'))
          .thenAnswer((_) => failing.future);
      cubit = build();
      load = cubit.load();
      await cubit.close();
      failing.completeError(Exception());
      await load;
      // Closed while copying.
      when(() => sales.getListingPhotos('sale-id')).thenAnswer((_) async => []);
      final copy = Completer<ListingPhoto>();
      when(
        () => sales.copyRoomPhoto(any(), sourcePath: any(named: 'sourcePath')),
      ).thenAnswer((_) => copy.future);
      cubit = build();
      load = cubit.load();
      await pumpEventQueue();
      await cubit.close();
      copy.complete(photo('z'));
      await load;
      // Closed while uploading / changing.
      final upload = Completer<ListingPhoto>();
      when(() => sales.uploadListingPhoto(any(), bytes: any(named: 'bytes')))
          .thenAnswer((_) => upload.future);
      when(() => sales.deleteListingPhoto(any())).thenAnswer((_) async {});
      cubit = build(
        sale: Sale(
          id: 'sale-id',
          formula: SaleFormula.essentiel,
          stage: SaleStage.mandateSigned,
          photosImportedAt: DateTime(2026),
        ),
      );
      await cubit.load();
      cubit.addFromCamera(processedPhoto());
      await pumpEventQueue();
      final removing = cubit.remove(photo('a'));
      await cubit.close();
      upload.complete(photo('u'));
      await removing;
      await pumpEventQueue();
    });

    test('state copy keeps values', () {
      const state = ListingPhotosState();
      expect(state.copyWith(), state);
      expect(state.props, hasLength(8));
    });
  });
}
