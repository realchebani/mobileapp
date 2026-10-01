import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:property_repository/property_repository.dart';

part 'surfaces_state.dart';

/// The rooms table of V5c and its persistence in `rooms`.
///
/// Rooms are edited locally; [submit] writes them. Each new room gets its
/// id (a UUID) as soon as it is added, so writing it is an upsert by id:
/// retrying after a failure (even one where the insert succeeded but its
/// answer was lost) updates the row instead of inserting it twice.
class SurfacesCubit extends Cubit<SurfacesState> {
  new({
    required this._propertyRepository,
    required this._propertyId,
    List<Room> rooms = const [],
    String Function()? generateId,
    this._timeout = defaultTimeout,
  }) : _saved = [...rooms],
       _generateId = generateId ?? randomUuid,
       super(SurfacesState(rooms: rooms));

  /// Delay after which a write is considered failed.
  static const defaultTimeout = Duration(seconds: 15);

  final PropertyRepository _propertyRepository;
  final String _propertyId;
  final String Function() _generateId;
  final Duration _timeout;

  /// The rows currently stored, updated after each successful write.
  List<Room> _saved;

  /// Ids of the rooms whose write failed: the row may exist anyway (its
  /// answer lost), so it is deleted if the room is removed meanwhile.
  final Set<String> _uncertain = {};

  void _edit(List<Room> Function(List<Room> rooms) change) {
    if (isClosed || state.isSubmitting) return;
    emit(state.copyWith(rooms: change(state.rooms)));
  }

  /// Adds a room at the end of the table.
  void roomAdded(RoomInput input) => _edit(
    (rooms) => [
      ...rooms,
      _apply(
        Room(propertyId: _propertyId, id: _generateId(), name: '', areaM2: 0),
        input,
      ),
    ],
  );

  /// Replaces the answers of the room [id] (keeping its other data).
  void roomEdited(String id, RoomInput input) => _edit(
    (rooms) => [
      for (final room in rooms)
        if (room.id == id) _apply(room, input) else room,
    ],
  );

  /// Removes the room [id] (deleted from the dossier on submit).
  void roomDeleted(String id) => _edit(
    (rooms) => [
      for (final room in rooms)
        if (room.id != id) room,
    ],
  );

  /// "Tout est correct, continuer": shows the error when there is no
  /// living-space room; otherwise deletes the removed rooms, then writes the
  /// new and changed ones (unchanged rows are not written), in table order.
  Future<void> submit() async {
    if (state.isSubmitting) return;
    if (!state.isValid) {
      emit(
        state.copyWith(
          showErrors: true,
          submitAttempts: state.submitAttempts + 1,
          submission: SurfacesSubmission.idle,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        showErrors: true,
        submission: SurfacesSubmission.inProgress,
      ),
    );
    final wanted = [
      for (final (index, room) in state.rooms.indexed)
        _withSortOrder(room, index),
    ];
    try {
      final wantedIds = {for (final room in wanted) room.id};
      final storedIds = {for (final row in _saved) row.id!, ..._uncertain};
      for (final id in storedIds) {
        if (wantedIds.contains(id)) continue;
        await _propertyRepository.deleteRoom(id).timeout(_timeout);
        _uncertain.remove(id);
        if (isClosed) return;
        _saved = [
          for (final saved in _saved)
            if (saved.id != id) saved,
        ];
      }
      final result = <Room>[];
      for (final room in wanted) {
        final stored = _saved.where((saved) => saved.id == room.id);
        if (stored.isNotEmpty && stored.first == room) {
          result.add(stored.first);
          continue;
        }
        _uncertain.add(room.id!);
        final saved = await _propertyRepository
            .saveRoom(room)
            .timeout(_timeout);
        _uncertain.remove(room.id);
        // Recorded at once, so that a retry does not write it again.
        _saved = [
          for (final other in _saved)
            if (other.id != saved.id) other,
          saved,
        ];
        result.add(saved);
        if (isClosed) return;
      }
      emit(
        state.copyWith(
          savedRooms: result,
          submission: SurfacesSubmission.success,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      // The rows stored so far, for the tunnel to stay in sync.
      emit(
        state.copyWith(
          savedRooms: [..._saved]
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
          submission: SurfacesSubmission.failure,
        ),
      );
    }
  }

  /// [room] with the answers of [input].
  static Room _apply(Room room, RoomInput input) => Room(
    id: room.id,
    propertyId: room.propertyId,
    name: input.name,
    level: input.level,
    sortOrder: room.sortOrder,
    areaM2: RoomArea.round(input.areaM2),
    ceilingHeightM: room.ceilingHeightM,
    floorCovering: input.floorCovering,
    glazing: input.glazing,
    isMain: input.isMain && !input.isAnnex,
    isAnnex: input.isAnnex,
    source: room.source,
    photosCount: room.photosCount,
    scanData: room.scanData,
  );

  static Room _withSortOrder(Room room, int sortOrder) => Room(
    id: room.id,
    propertyId: room.propertyId,
    name: room.name,
    level: room.level,
    sortOrder: sortOrder,
    areaM2: room.areaM2,
    ceilingHeightM: room.ceilingHeightM,
    floorCovering: room.floorCovering,
    glazing: room.glazing,
    isMain: room.isMain,
    isAnnex: room.isAnnex,
    source: room.source,
    photosCount: room.photosCount,
    scanData: room.scanData,
  );

  static final Random _random = Random.secure();

  /// A random (version 4) UUID.
  static String randomUuid() {
    final bytes = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
