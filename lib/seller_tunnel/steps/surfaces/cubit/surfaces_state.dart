part of 'surfaces_cubit.dart';

/// Progress of "C’est correct, continuer": the rooms are saved first,
/// then the view hands the total to the tunnel cubit.
enum SurfacesSubmission { idle, inProgress, success, failure }

/// The rooms of V5c · Récapitulatif des surfaces, as edited.
final class SurfacesState extends Equatable {
  const new({
    this.rooms = const [],
    this.savedRooms = const [],
    this.showErrors = false,
    this.submitAttempts = 0,
    this.submission = SurfacesSubmission.idle,
    this.dictated = const {},
    this.lastDictatedId,
    this.savingRoomId,
    this.photosRoom,
    this.toConfirm = const {},
    this.pendingResolutions = const {},
  });

  /// The rooms of the table, in order (each has its id, even before it is
  /// saved).
  final List<Room> rooms;

  /// The rooms stored after the last submission (all of them on success,
  /// those written so far on failure).
  final List<Room> savedRooms;

  /// Whether errors are shown (after a first "Continuer").
  final bool showErrors;

  /// Incremented on each rejected "Continuer" (to reveal the error).
  final int submitAttempts;

  final SurfacesSubmission submission;

  /// Ids of the rooms created or changed by voice on this visit ("Dicté").
  final Set<String> dictated;

  /// The room dictated last ("la dernière").
  final String? lastDictatedId;

  /// The room being saved before its photos are opened (EPIC-15).
  final String? savingRoomId;

  /// The stored row of the room whose photos open (after
  /// `SurfacesCubit.preparePhotos`), or null when it could not be written.
  final Room? photosRoom;

  /// The rooms said on another step and not confirmed nor changed yet
  /// (EPIC-16, « À confirmer »): room id → pending answer id.
  final Map<String, String> toConfirm;

  /// The pending rooms, resolved by the last submission: closed once the
  /// step is saved.
  final Map<PendingResolution, List<String>> pendingResolutions;

  /// Photos of all the rooms (EPIC-15).
  int get photosCount => rooms.fold(0, (sum, room) => sum + room.photosCount);

  /// The "pièces principales", which need a photo to send the dossier.
  List<Room> get mainRooms => [
    for (final room in rooms)
      if (room.isMain) room,
  ];

  /// The main rooms without a photo yet.
  List<Room> get mainRoomsWithoutPhotos => [
    for (final room in mainRooms)
      if (room.photosCount == 0) room,
  ];

  /// The rooms dictated on this visit, in table order.
  List<Room> get dictatedRooms => [
    for (final room in rooms)
      if (dictated.contains(room.id)) room,
  ];

  bool get isSubmitting =>
      submission == SurfacesSubmission.inProgress || savingRoomId != null;

  /// At least one living-space room (not an annex) is needed to continue.
  bool get isValid => rooms.any((room) => !room.isAnnex);

  /// Living area (surface habitable): the sum of the rooms that are not
  /// annexes (m², 2 decimals).
  double get livingArea => _sum(rooms.where((room) => !room.isAnnex));

  /// Area of the annexes (m², 2 decimals).
  double get annexArea => _sum(rooms.where((room) => room.isAnnex));

  /// Whether some rooms are annexes.
  bool get hasAnnexes => rooms.any((room) => room.isAnnex);

  static double _sum(Iterable<Room> rooms) =>
      RoomArea.round(rooms.fold(0, (sum, room) => sum + room.areaM2));

  /// Number of "pièces principales".
  int get mainRoomsCount => rooms.where((room) => room.isMain).length;

  /// The rooms grouped by level (levels in their order, rooms without a
  /// level last), each group in table order.
  List<(RoomLevel?, List<Room>)> get roomsByLevel => [
    for (final level in [...RoomLevel.values, null])
      if (rooms.where((room) => room.level == level).toList() case final group
          when group.isNotEmpty)
        (level, group),
  ];

  SurfacesState copyWith({
    List<Room>? rooms,
    List<Room>? savedRooms,
    bool? showErrors,
    int? submitAttempts,
    SurfacesSubmission? submission,
    Set<String>? dictated,
    String? Function()? lastDictatedId,
    String? Function()? savingRoomId,
    Room? Function()? photosRoom,
    Map<String, String>? toConfirm,
    Map<PendingResolution, List<String>>? pendingResolutions,
  }) {
    return SurfacesState(
      rooms: rooms ?? this.rooms,
      savedRooms: savedRooms ?? this.savedRooms,
      showErrors: showErrors ?? this.showErrors,
      submitAttempts: submitAttempts ?? this.submitAttempts,
      submission: submission ?? this.submission,
      dictated: dictated ?? this.dictated,
      lastDictatedId: lastDictatedId == null
          ? this.lastDictatedId
          : lastDictatedId(),
      savingRoomId: savingRoomId == null ? this.savingRoomId : savingRoomId(),
      photosRoom: photosRoom == null ? this.photosRoom : photosRoom(),
      toConfirm: toConfirm ?? this.toConfirm,
      pendingResolutions: pendingResolutions ?? this.pendingResolutions,
    );
  }

  @override
  List<Object?> get props => [
    rooms,
    savedRooms,
    showErrors,
    submitAttempts,
    submission,
    dictated,
    lastDictatedId,
    savingRoomId,
    photosRoom,
    toConfirm,
    pendingResolutions,
  ];
}
