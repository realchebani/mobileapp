import 'dart:async';
import 'dart:math';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_form.dart';
import 'package:property_repository/property_repository.dart';

part 'surfaces_state.dart';

/// The rooms table of V5c and its persistence in `rooms`.
///
/// Rooms are edited locally; [submit] writes them. Each new room gets its
/// id (a UUID) as soon as it is added, so writing it is an upsert by id:
/// retrying after a failure (even one where the insert succeeded but its
/// answer was lost) updates the row instead of inserting it twice.
///
/// The rooms dictated to the voice agent (EPIC-14, V5c dictation) are
/// applied to the table the same way ([applyVoiceTurn]), `source = voice`.
class SurfacesCubit extends Cubit<SurfacesState>
    with VoiceFormMixin<SurfacesState> {
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
        // Its photos first (EPIC-15): their files would stay otherwise.
        await _propertyRepository.deleteRoomPhotos(id).timeout(_timeout);
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

  /// Writes the room [id] now (before its photos are taken, EPIC-15): a
  /// photo needs its room row. Then [SurfacesState.photosRoom] is the
  /// stored row, or null when it could not be written (retried on
  /// "Continuer" as usual).
  Future<void> preparePhotos(String id) async {
    if (state.isSubmitting) return;
    final index = state.rooms.indexWhere((room) => room.id == id);
    if (index < 0) return;
    final room = _withSortOrder(state.rooms[index], index);
    final stored = _saved.where((saved) => saved.id == id).firstOrNull;
    if (stored != null && stored == room) {
      emit(state.copyWith(photosRoom: () => stored));
      return;
    }
    emit(state.copyWith(savingRoomId: () => id, photosRoom: () => null));
    try {
      _uncertain.add(id);
      final saved = await _propertyRepository.saveRoom(room).timeout(_timeout);
      _uncertain.remove(id);
      _saved = [
        for (final other in _saved)
          if (other.id != id) other,
        saved,
      ];
      if (isClosed) return;
      emit(state.copyWith(savingRoomId: () => null, photosRoom: () => saved));
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(savingRoomId: () => null));
    }
  }

  /// The room [id] now has [count] photos (kept by the database; recorded
  /// here so that the row is not written again for it).
  void photosChanged(String id, int count) {
    Room counted(Room room) =>
        room.id == id ? _withPhotosCount(room, count) : room;
    _saved = [for (final room in _saved) counted(room)];
    if (isClosed) return;
    emit(
      state.copyWith(rooms: [for (final room in state.rooms) counted(room)]),
    );
  }

  static Room _withPhotosCount(Room room, int count) => Room(
    id: room.id,
    propertyId: room.propertyId,
    name: room.name,
    level: room.level,
    sortOrder: room.sortOrder,
    areaM2: room.areaM2,
    ceilingHeightM: room.ceilingHeightM,
    floorCovering: room.floorCovering,
    glazing: room.glazing,
    isMain: room.isMain,
    isAnnex: room.isAnnex,
    source: room.source,
    photosCount: count,
    scanData: room.scanData,
    description: room.description,
  );

  /// [room] with the answers of [input]. A room read on a plan whose name
  /// or area is corrected becomes a typed one (its values are no longer
  /// those of the document).
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
    source:
        room.source == RoomSource.plan &&
            (input.name != room.name ||
                RoomArea.round(input.areaM2) != room.areaM2)
        ? RoomSource.manual
        : room.source,
    photosCount: room.photosCount,
    scanData: room.scanData,
    description: input.description,
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
    description: room.description,
  );

  // ---------------------------------------------------------------------
  // Voice (EPIC-14): rooms dictated to the agent.
  // ---------------------------------------------------------------------

  @override
  bool get acceptsVoice => !state.isSubmitting;

  /// The short reference of each room sent to the agent (R1… in table
  /// order).
  static Map<String, Room> _byRef(List<Room> rooms) => {
    for (final (i, room) in rooms.indexed) 'R${i + 1}': room,
  };

  @override
  AgentTurnContext get voiceContext {
    final refs = _byRef(state.rooms);
    return AgentTurnContext(
      rooms: [
        for (final MapEntry(key: ref, value: room) in refs.entries)
          AgentRoom(
            ref: ref,
            name: room.name,
            areaM2: room.areaM2,
            level: room.level?.value,
            floorCovering: room.floorCovering,
            glazing: room.glazing?.value,
            ceilingHeightM: room.ceilingHeightM,
            isAnnex: room.isAnnex,
          ),
      ],
      lastRoomRef: [
        for (final MapEntry(key: ref, value: room) in refs.entries)
          if (room.id != null && room.id == state.lastDictatedId) ref,
      ].firstOrNull,
    );
  }

  /// R1… become the room ids (`id:<id>`).
  @override
  AgentTurn resolveVoiceTurn(SurfacesState state, AgentTurn turn) {
    final refs = _byRef(state.rooms);
    return turn.withEntityOps([
      for (final op in turn.entityOps)
        if (refs[op.target]?.id case final id?) op.withTarget('id:$id') else op,
    ]);
  }

  @override
  SurfacesState applyVoiceTurn(SurfacesState state, AgentTurn turn) {
    final refs = {
      ..._byRef(state.rooms),
      for (final room in state.rooms) 'id:${room.id}': room,
    };
    var rooms = [...state.rooms];
    final dictated = {...state.dictated};
    var last = state.lastDictatedId;
    for (final op in turn.entityOps) {
      if (op.entity != AgentEntity.room) continue;
      final values = op.values;
      if (op.isNew && op.op == AgentEntityOp.create) {
        final room = _dictatedRoom(values, rooms);
        if (room == null) continue;
        rooms = [...rooms, room];
        dictated.add(room.id!);
        last = room.id;
        continue;
      }
      final target = refs[op.target];
      if (target == null || !rooms.any((room) => room.id == target.id)) {
        continue;
      }
      if (op.op == AgentEntityOp.delete) {
        rooms = [
          for (final room in rooms)
            if (room.id != target.id) room,
        ];
        dictated.remove(target.id);
        if (last == target.id) last = null;
        continue;
      }
      rooms = [
        for (final room in rooms)
          if (room.id == target.id) _withVoiceValues(room, values) else room,
      ];
      dictated.add(target.id!);
      last = target.id;
    }
    return state.copyWith(
      rooms: rooms,
      dictated: dictated,
      lastDictatedId: () => last,
    );
  }

  /// A new room from the agent's [values]: its kind decides main / annex,
  /// bedrooms are numbered like on the room form, and a level that was not
  /// said is the one of the last room (never guessed by the AI).
  Room? _dictatedRoom(Map<String, Object?> values, List<Room> rooms) {
    final name = values['name'];
    final area = values['area_m2'];
    if (name is! String || name.trim().isEmpty || area is! num) return null;
    final kind = RoomSuggestion.byKind(values['kind']);
    final level =
        parseDbEnum(RoomLevel.values, values['level']) ??
        rooms.lastOrNull?.level ??
        RoomLevel.groundFloor;
    final isAnnex = kind?.isAnnex ?? false;
    return _withVoiceValues(
      Room(
        id: _generateId(),
        propertyId: _propertyId,
        name: kind?.isNumbered ?? false
            ? RoomSuggestion.numbered(name.trim(), [
                for (final room in rooms) room.name,
              ])
            : name.trim(),
        areaM2: 0,
        level: level,
        isMain: (kind?.isMain ?? false) && !isAnnex,
        isAnnex: isAnnex,
        source: RoomSource.voice,
      ),
      {...values, 'level': level.value},
    );
  }

  /// [room] with the values said ([values] as stored).
  static Room _withVoiceValues(Room room, Map<String, Object?> values) {
    String? text(String key, String? current) =>
        values.containsKey(key) ? (values[key] as String?)?.trim() : current;
    final area = values['area_m2'];
    final height = values['ceiling_height_m'];
    return Room(
      id: room.id,
      propertyId: room.propertyId,
      name: room.name,
      level: values.containsKey('level')
          ? parseDbEnum(RoomLevel.values, values['level']) ?? room.level
          : room.level,
      sortOrder: room.sortOrder,
      areaM2: area is num ? RoomArea.round(area.toDouble()) : room.areaM2,
      ceilingHeightM: height is num ? height.toDouble() : room.ceilingHeightM,
      floorCovering: text('floor_covering', room.floorCovering),
      glazing: values.containsKey('glazing')
          ? parseDbEnum(Glazing.values, values['glazing']) ?? room.glazing
          : room.glazing,
      isMain: room.isMain,
      isAnnex: room.isAnnex,
      source: room.source,
      photosCount: room.photosCount,
      scanData: room.scanData,
      description: text('description', room.description),
    );
  }

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
