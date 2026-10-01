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
/// principales" (living room, bedrooms, office) and [isAnnex] rooms are
/// annexes (not part of the living area).
enum RoomSuggestion {
  entrance(),
  livingRoom(isMain: true),
  kitchen(),
  bedroom(isMain: true),
  bathroom(),
  showerRoom(),
  toilet(),
  office(isMain: true),
  hallway(),
  storeroom(isAnnex: true),
  laundry(isAnnex: true),
  garage(isAnnex: true),
  basement(isAnnex: true),
  other();

  new({this.isMain = false, this.isAnnex = false});

  /// Whether this kind of room is a main room by default.
  final bool isMain;

  /// Whether this kind of room is an annex by default.
  final bool isAnnex;

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
    hallway => l10n.surfacesRoomHallway,
    storeroom => l10n.surfacesRoomStoreroom,
    laundry => l10n.surfacesRoomLaundry,
    garage => l10n.surfacesRoomGarage,
    basement => l10n.surfacesRoomBasement,
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
