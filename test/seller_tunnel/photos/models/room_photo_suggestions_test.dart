import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  final l10n = AppLocalizationsFr();
  const room = RoomInput(
    name: 'Séjour',
    level: RoomLevel.groundFloor,
    areaM2: 30,
    floorCovering: 'parquet',
    isMain: true,
    description: 'Lumineux. Fissure au plafond',
  );

  RoomPhoto analysed(String id, RoomPhotoAnalysis analysis) =>
      testRoomPhoto(id, analysis: analysis);

  group(RoomPhotoSuggestions, () {
    test('proposes the most frequent values that change the room', () {
      final suggestions = RoomPhotoSuggestions.of(
        room: room,
        currentKind: RoomSuggestion.livingRoom,
        photos: [
          analysed(
            'a',
            const RoomPhotoAnalysis(
              roomKind: 'kitchen',
              floorCovering: 'carrelage',
              glazing: Glazing.double,
              conditionNotes: ['Fissure au plafond', 'Joints noircis'],
              personalItems: ['Courrier'],
              peopleVisible: true,
            ),
          ),
          analysed(
            'b',
            const RoomPhotoAnalysis(
              roomKind: 'kitchen',
              floorCovering: 'carrelage',
              conditionNotes: ['joints noircis'],
              personalItems: ['courrier', 'Photos de famille'],
            ),
          ),
          analysed('c', const RoomPhotoAnalysis(roomKind: 'livingRoom')),
          testRoomPhoto('d'),
        ],
      );
      expect(suggestions.kind, RoomSuggestion.kitchen);
      expect(suggestions.floorCovering, FloorCovering.tiles);
      expect(suggestions.glazing, Glazing.double);
      expect(suggestions.conditionNotes, ['Joints noircis']);
      expect(suggestions.personalItems, ['Courrier', 'Photos de famille']);
      expect(suggestions.peoplePhotoIds, ['a']);
      expect(suggestions.analyzedCount, 3);
      expect(suggestions.hasProposals, isTrue);
    });

    test('proposes nothing that the room already says', () {
      final suggestions = RoomPhotoSuggestions.of(
        room: room,
        currentKind: RoomSuggestion.livingRoom,
        photos: [
          analysed(
            'a',
            const RoomPhotoAnalysis(
              roomKind: 'livingRoom',
              floorCovering: 'parquet',
              conditionNotes: ['fissure au plafond'],
            ),
          ),
          analysed('b', const RoomPhotoAnalysis(roomKind: 'other')),
          analysed('c', const RoomPhotoAnalysis(roomKind: 'other')),
        ],
      );
      expect(suggestions.kind, isNull);
      expect(suggestions.floorCovering, isNull);
      expect(suggestions.glazing, isNull);
      expect(suggestions.hasProposals, isFalse);
      expect(
        RoomPhotoSuggestions.of(room: room, photos: const []),
        const RoomPhotoSuggestions(),
      );
    });

    test('kindOfName reads the kind of a room name', () {
      expect(
        RoomPhotoSuggestions.kindOfName('Chambre 2', l10n),
        RoomSuggestion.bedroom,
      );
      expect(
        RoomPhotoSuggestions.kindOfName(' séjour ', l10n),
        RoomSuggestion.livingRoom,
      );
      expect(RoomPhotoSuggestions.kindOfName('Véranda', l10n), isNull);
      expect(RoomPhotoSuggestions.kindOfName('Autre', l10n), isNull);
    });
  });

  group('RoomSuggestionChanges', () {
    test('withKind names and flags the room as the kind', () {
      final bedroom = room.withKind(RoomSuggestion.bedroom, l10n, [
        'Chambre 1',
      ]);
      expect(bedroom.name, 'Chambre 2');
      expect(bedroom.isMain, isTrue);
      final garage = room.withKind(RoomSuggestion.garage, l10n, const []);
      expect(garage.name, 'Garage');
      expect(garage.isMain, isFalse);
      expect(garage.isAnnex, isTrue);
      expect(garage.areaM2, 30);
    });

    test('withFloorCovering and withGlazing', () {
      expect(
        room.withFloorCovering(FloorCovering.tiles).floorCovering,
        'carrelage',
      );
      expect(room.withGlazing(Glazing.triple).glazing, Glazing.triple);
    });

    test('withNote adds a sentence to the description', () {
      expect(
        room.withNote('Joints noircis').description,
        'Lumineux. Fissure au plafond. Joints noircis',
      );
      const ended = RoomInput(
        name: 'A',
        level: null,
        areaM2: 1,
        description: 'Fini.',
      );
      expect(ended.withNote('Note').description, 'Fini. Note');
      const empty = RoomInput(name: 'A', level: null, areaM2: 1);
      expect(empty.withNote('Note').description, 'Note');
      final long = RoomInput(
        name: 'A',
        level: null,
        areaM2: 1,
        description: 'x' * 599,
      );
      // « Notes complémentaires » (EPIC-16): 600 characters.
      expect(long.withNote('Une note').description, hasLength(600));
    });
  });
}
