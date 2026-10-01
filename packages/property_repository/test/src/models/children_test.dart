import 'package:property_repository/property_repository.dart';
import 'package:test/test.dart';

void main() {
  test('PropertyOwner round-trips', () {
    const owner = PropertyOwner(
      id: 'o1',
      propertyId: 'p1',
      position: 1,
      profileId: 'u1',
      firstName: 'Sophie',
      lastName: 'Durand',
      phone: '+33612345678',
      email: 'sophie@example.com',
    );
    expect(PropertyOwner.fromJson(owner.toJson()), owner);
    const newOwner = PropertyOwner(
      propertyId: 'p1',
      position: 2,
      firstName: 'Marc',
      lastName: 'Durand',
    );
    expect(newOwner.toJson().containsKey('id'), isFalse);
    expect(PropertyOwner.fromJson(newOwner.toJson()), newOwner);
  });

  test('PropertyParcel round-trips', () {
    const parcel = PropertyParcel(
      id: 'pa1',
      propertyId: 'p1',
      idu: '690430000AB0098',
      codeInsee: '69043',
      section: 'AB',
      numero: '0098',
      areaM2: 540,
      geometry: {'type': 'MultiPolygon', 'coordinates': <Object>[]},
    );
    expect(PropertyParcel.fromJson(parcel.toJson()), parcel);
    expect(
      PropertyParcel.fromJson(const {'property_id': 'p1', 'idu': 'x'}).source,
      'apicarto',
    );
  });

  test('PreviousEstimate round-trips, storing a month', () {
    final estimate = PreviousEstimate(
      id: 'e1',
      propertyId: 'p1',
      priceEur: 510000,
      estimatedMonth: DateTime(2025, 3),
      agencyName: 'Agence du Centre',
    );
    expect(estimate.toJson()['estimated_month'], '2025-03-01');
    expect(PreviousEstimate.fromJson(estimate.toJson()), estimate);
    const bare = PreviousEstimate(propertyId: 'p1', priceEur: 1);
    expect(bare.toJson()['estimated_month'], isNull);
    expect(PreviousEstimate.fromJson(bare.toJson()), bare);
  });

  test('Room round-trips and defaults', () {
    const room = Room(
      id: 'r1',
      propertyId: 'p1',
      name: 'Séjour',
      areaM2: 38.5,
      level: RoomLevel.groundFloor,
      sortOrder: 2,
      ceilingHeightM: 2.5,
      floorCovering: 'Parquet chêne',
      glazing: Glazing.double,
      isMain: true,
      isAnnex: true,
      source: MeasurementMethod.scan,
      photosCount: 4,
      scanData: {'points': 12},
    );
    expect(Room.fromJson(room.toJson()), room);
    final bare = Room.fromJson(const {
      'property_id': 'p1',
      'name': 'WC',
      'area_m2': 2,
    });
    expect(bare, const Room(propertyId: 'p1', name: 'WC', areaM2: 2));
    expect(bare.isAnnex, isFalse);
  });

  test('LifestyleItem round-trips and defaults', () {
    const item = LifestyleItem(
      id: 'l1',
      propertyId: 'p1',
      kind: LifestyleItemKind.watchPoint,
      label: 'Rue chargée',
      sortOrder: 1,
      source: LifestyleItemSource.voice,
    );
    expect(LifestyleItem.fromJson(item.toJson()), item);
    expect(
      LifestyleItem.fromJson(const {'property_id': 'p1', 'label': 'x'}),
      const LifestyleItem(
        propertyId: 'p1',
        kind: LifestyleItemKind.asset,
        label: 'x',
      ),
    );
  });

  test('PropertyDocument round-trips and defaults', () {
    final document = PropertyDocument(
      id: 'd1',
      propertyId: 'p1',
      kind: DocumentKind.titleDeed,
      storagePath: 'u1/p1/1_titre.pdf',
      fileName: 'titre.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1024,
      status: DocumentStatus.analyzed,
      extracted: const {'year': 2012},
      uploadedAt: DateTime.utc(2026, 9, 30),
    );
    expect(PropertyDocument.fromJson(document.toJson()), document);
    expect(
      PropertyDocument.fromJson(const {
        'id': 'd',
        'property_id': 'p',
        'kind': 'nope',
        'storage_path': 's',
      }),
      const PropertyDocument(
        id: 'd',
        propertyId: 'p',
        kind: DocumentKind.other,
        storagePath: 's',
      ),
    );
  });
}
