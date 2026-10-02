import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/models/document_checklist.dart';
import 'package:property_repository/property_repository.dart';

const _house = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
);

Room _room(String id, {bool isMain = true, int photos = 0}) => Room(
  id: id,
  propertyId: 'property-id',
  name: id,
  areaM2: 10,
  isMain: isMain,
  photosCount: photos,
);

void main() {
  group('DocumentChecklist · photos (EPIC-15)', () {
    test('lists the main rooms without a photo', () {
      final checklist = DocumentChecklist.of(
        _house,
        const [],
        rooms: [
          _room('Séjour'),
          _room('Chambre', photos: 2),
          _room('WC', isMain: false),
        ],
      );
      expect([for (final r in checklist.missingPhotoRooms) r.name], ['Séjour']);
      // The title deed weighs more than the photos.
      expect(checklist.photosNextBest, isFalse);
    });

    test('the photos count in the score, proportionally', () {
      const documents = [
        PropertyDocument(
          id: 't',
          propertyId: 'property-id',
          kind: DocumentKind.titleDeed,
          storagePath: 't',
        ),
        PropertyDocument(
          id: 'i',
          propertyId: 'property-id',
          kind: DocumentKind.identityDocument,
          storagePath: 'i',
        ),
        PropertyDocument(
          id: 'd',
          propertyId: 'property-id',
          kind: DocumentKind.diagnostics,
          storagePath: 'd',
        ),
      ];
      int score(List<Room> rooms) =>
          DocumentChecklist.of(_house, documents, rooms: rooms).score;
      final none = score([_room('A'), _room('B')]);
      final half = score([_room('A', photos: 1), _room('B')]);
      final all = score([_room('A', photos: 1), _room('B', photos: 3)]);
      expect(none, lessThan(half));
      expect(half, lessThan(all));
      final missing = DocumentChecklist.of(
        _house,
        documents,
        rooms: [_room('A')],
      );
      expect(missing.photosNextBest, isTrue);
      expect(missing.nextBestKind, isNull);
    });

    test('no photo needed without main rooms or for a garage', () {
      expect(DocumentChecklist.of(_house, const []).missingPhotoRooms, isEmpty);
      final garage = DocumentChecklist.of(
        const Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.parking,
        ),
        const [],
        rooms: [_room('Box')],
      );
      expect(garage.missingPhotoRooms, isEmpty);
      expect(garage.photosNextBest, isFalse);
    });
  });
}
