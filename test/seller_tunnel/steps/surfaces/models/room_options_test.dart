import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('fr'));

  test('FloorCovering parses and labels the stored values', () {
    expect(
      [for (final c in FloorCovering.values) c.label(l10n)],
      [
        'Parquet chêne',
        'Parquet',
        'Carrelage',
        'Moquette',
        'Béton ciré',
        'Stratifié',
        'Vinyle',
        'Autre',
      ],
    );
    expect(FloorCovering.parse('beton_cire'), FloorCovering.polishedConcrete);
    expect(FloorCovering.parse('marbre'), isNull);
    expect(FloorCovering.labelOf('parquet_chene', l10n), 'Parquet chêne');
    expect(FloorCovering.labelOf('Marbre', l10n), 'Marbre');
    expect(FloorCovering.labelOf(null, l10n), isNull);
  });

  test('RoomSuggestion labels, main rooms and numbering', () {
    expect(
      [for (final s in RoomSuggestion.values) s.label(l10n)],
      [
        'Entrée',
        'Séjour',
        'Cuisine',
        'Chambre',
        'Salle de bain',
        'Salle d’eau',
        'WC',
        'Bureau',
        'Cellier',
        'Dégagement',
        'Garage',
        'Autre',
      ],
    );
    expect(
      [
        for (final s in RoomSuggestion.values)
          if (s.isMain) s,
      ],
      [
        RoomSuggestion.livingRoom,
        RoomSuggestion.bedroom,
        RoomSuggestion.office,
      ],
    );
    expect(RoomSuggestion.bedroom.isNumbered, isTrue);
    expect(RoomSuggestion.office.isNumbered, isFalse);
  });

  test('levels and glazings are labelled', () {
    expect(
      [for (final level in RoomLevel.values) level.label(l10n)],
      ['Sous-sol', 'Rez-de-chaussée', 'Étage', 'Étage 2', 'Combles'],
    );
    expect(
      [for (final glazing in Glazing.values) glazing.label(l10n)],
      ['Simple', 'Double', 'Triple'],
    );
  });

  test('RoomInput.fromRoom copies the answers', () {
    const room = Room(
      id: 'r1',
      propertyId: 'p',
      name: 'Séjour',
      level: RoomLevel.groundFloor,
      areaM2: 38.5,
      floorCovering: 'parquet',
      glazing: Glazing.double,
      isMain: true,
    );
    expect(
      RoomInput.fromRoom(room),
      const RoomInput(
        name: 'Séjour',
        level: RoomLevel.groundFloor,
        areaM2: 38.5,
        floorCovering: 'parquet',
        glazing: Glazing.double,
        isMain: true,
      ),
    );
  });
}
