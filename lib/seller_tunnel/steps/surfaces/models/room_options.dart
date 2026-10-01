import 'package:mobileapp/l10n/l10n.dart';
import 'package:property_repository/property_repository.dart';

/// Floor coverings proposed in the room form (`rooms.floor_covering` is a
/// free text column: the [value] is stored).
enum FloorCovering {
  oakParquet('parquet_chene'),
  parquet('parquet'),
  tiles('carrelage'),
  carpet('moquette'),
  polishedConcrete('beton_cire'),
  laminate('stratifie'),
  vinyl('vinyle'),
  other('autre');

  new(this.value);

  /// Stored value.
  final String value;

  /// The covering stored as [value], or null when it is not one of these.
  static FloorCovering? parse(String? value) {
    for (final covering in values) {
      if (covering.value == value) return covering;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
    oakParquet => l10n.surfacesCoveringOakParquet,
    parquet => l10n.surfacesCoveringParquet,
    tiles => l10n.surfacesCoveringTiles,
    carpet => l10n.surfacesCoveringCarpet,
    polishedConcrete => l10n.surfacesCoveringPolishedConcrete,
    laminate => l10n.surfacesCoveringLaminate,
    vinyl => l10n.surfacesCoveringVinyl,
    other => l10n.surfacesCoveringOther,
  };

  /// Label of a stored covering; an unknown value is shown as stored.
  static String? labelOf(String? value, AppLocalizations l10n) =>
      parse(value)?.label(l10n) ?? value;
}

/// Quick names of the room form; [isMain] rooms are "pièces
/// principales" (living room, bedrooms, office).
enum RoomSuggestion {
  entrance(isMain: false),
  livingRoom(isMain: true),
  kitchen(isMain: false),
  bedroom(isMain: true),
  bathroom(isMain: false),
  showerRoom(isMain: false),
  toilet(isMain: false),
  office(isMain: true),
  storeroom(isMain: false),
  hallway(isMain: false),
  garage(isMain: false),
  other(isMain: false);

  new({required this.isMain});

  /// Whether this kind of room is a main room by default.
  final bool isMain;

  /// Several rooms of this kind are numbered ("Chambre 2").
  bool get isNumbered => this == bedroom;

  String label(AppLocalizations l10n) => switch (this) {
    entrance => l10n.surfacesRoomEntrance,
    livingRoom => l10n.surfacesRoomLivingRoom,
    kitchen => l10n.surfacesRoomKitchen,
    bedroom => l10n.surfacesRoomBedroom,
    bathroom => l10n.surfacesRoomBathroom,
    showerRoom => l10n.surfacesRoomShowerRoom,
    toilet => l10n.surfacesRoomToilet,
    office => l10n.surfacesRoomOffice,
    storeroom => l10n.surfacesRoomStoreroom,
    hallway => l10n.surfacesRoomHallway,
    garage => l10n.surfacesRoomGarage,
    other => l10n.surfacesRoomOther,
  };
}

/// Labels of the room levels.
extension RoomLevelLabel on RoomLevel {
  String label(AppLocalizations l10n) => switch (this) {
    RoomLevel.basement => l10n.surfacesLevelBasement,
    RoomLevel.groundFloor => l10n.surfacesLevelGroundFloor,
    RoomLevel.firstFloor => l10n.surfacesLevelFirstFloor,
    RoomLevel.secondFloor => l10n.surfacesLevelSecondFloor,
    RoomLevel.attic => l10n.surfacesLevelAttic,
  };
}

/// Labels of the glazings.
extension GlazingLabel on Glazing {
  String label(AppLocalizations l10n) => switch (this) {
    Glazing.single => l10n.surfacesGlazingSingle,
    Glazing.double => l10n.surfacesGlazingDouble,
    Glazing.triple => l10n.surfacesGlazingTriple,
  };
}
