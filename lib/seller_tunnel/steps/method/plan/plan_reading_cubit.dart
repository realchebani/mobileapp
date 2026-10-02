import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:property_repository/property_repository.dart';

/// Progress of the plan reading of V5 (EPIC-15).
enum PlanReadingStatus { idle, uploading, reading, saving }

/// What went wrong, told once (a snackbar).
enum PlanReadingNotice { uploadFailed, readFailed, quota, saveFailed }

/// Turns a photo of a plan into the JPEG sent to the vision AI (upright,
/// reduced, readable).
typedef PlanImageEncoder = Future<Uint8List> Function(Uint8List image);

/// Default [PlanImageEncoder]: 2 400 px, JPEG 85, in a background isolate.
Future<Uint8List> encodePlanImage(Uint8List image) =>
    Isolate.run(() => compressPage(image, (maxSide: 2400, quality: 85)));

final class PlanReadingState extends Equatable {
  const new({
    this.status = PlanReadingStatus.idle,
    this.document,
    this.reading,
    this.roomsSaved = false,
    this.notice,
    this.noticeCount = 0,
  });

  final PlanReadingStatus status;

  /// The plan stored by the last [PlanReadingCubit.store] (null while it
  /// is stored, or when it failed).
  final PropertyDocument? document;

  /// The rooms read by the last [PlanReadingCubit.read] (null while it
  /// reads, or when it failed).
  final PlanReading? reading;

  /// Whether the last [PlanReadingCubit.saveRooms] wrote every room.
  final bool roomsSaved;

  final PlanReadingNotice? notice;
  final int noticeCount;

  bool get isBusy => status != PlanReadingStatus.idle;

  PlanReadingState copyWith({
    required PlanReadingStatus status,
    PropertyDocument? Function()? document,
    PlanReading? Function()? reading,
    bool? roomsSaved,
    PlanReadingNotice? notice,
  }) => PlanReadingState(
    status: status,
    document: document == null ? this.document : document(),
    reading: reading == null ? this.reading : reading(),
    roomsSaved: roomsSaved ?? this.roomsSaved,
    notice: notice ?? this.notice,
    noticeCount: notice == null ? noticeCount : noticeCount + 1,
  );

  @override
  List<Object?> get props => [
    status,
    document,
    reading,
    roomsSaved,
    notice,
    noticeCount,
  ];
}

/// V5 · "Lire un plan": stores the photo of the plan as a `plan` document,
/// asks the vision AI for the rooms printed on it, then writes the rooms
/// the seller kept (`source = plan`).
class PlanReadingCubit extends Cubit<PlanReadingState> {
  new({
    required this._repository,
    required this._property,
    PlanImageEncoder? encode,
    String Function()? generateId,
    this._timeout = defaultTimeout,
  }) : _encode = encode ?? encodePlanImage,
       _generateId = generateId ?? generateUuidV4,
       super(const PlanReadingState());

  static const defaultTimeout = Duration(seconds: 15);

  /// Delay of the reading by the vision AI.
  static const readTimeout = Duration(seconds: 90);

  final PropertyRepository _repository;
  final Property _property;
  final PlanImageEncoder _encode;
  final String Function() _generateId;
  final Duration _timeout;

  /// Ids of the rooms to write, by position in the list given to
  /// [saveRooms]: a retry writes the same rows (upserts).
  final List<String> _roomIds = [];

  /// Stores [image] (a photo of the plan) as a document: then
  /// [PlanReadingState.document] is the stored plan, or null on failure
  /// (with a notice).
  Future<void> store(Uint8List image) async {
    if (state.isBusy) return;
    emit(
      state.copyWith(status: PlanReadingStatus.uploading, document: () => null),
    );
    try {
      final jpeg = await _encode(image);
      final document = await _repository
          .uploadDocument(
            ownerId: _property.ownerId,
            propertyId: _property.id,
            kind: DocumentKind.plan,
            fileName: 'plan.jpg',
            bytes: jpeg,
            mimeType: 'image/jpeg',
          )
          .timeout(_timeout * 2);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: PlanReadingStatus.idle,
          document: () => document,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          status: PlanReadingStatus.idle,
          notice: PlanReadingNotice.uploadFailed,
        ),
      );
    }
  }

  /// Asks the vision AI for the rooms printed on [document]: then
  /// [PlanReadingState.reading] holds them, or null on failure (with a
  /// notice).
  Future<void> read(PropertyDocument document) async {
    if (state.isBusy) return;
    emit(
      state.copyWith(status: PlanReadingStatus.reading, reading: () => null),
    );
    try {
      final reading = await _repository
          .readPlan(document.id)
          .timeout(readTimeout);
      if (isClosed) return;
      emit(
        state.copyWith(status: PlanReadingStatus.idle, reading: () => reading),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          status: PlanReadingStatus.idle,
          notice: error is VisionQuotaFailure
              ? PlanReadingNotice.quota
              : PlanReadingNotice.readFailed,
        ),
      );
    }
  }

  /// Writes [rooms] after the [existing] ones (`source = plan`), each
  /// recorded as soon as it is written: [onSaved] receives the rows stored
  /// so far. Then [PlanReadingState.roomsSaved] tells whether every room
  /// was written.
  Future<void> saveRooms(
    List<RoomInput> rooms, {
    required List<Room> existing,
    required void Function(List<Room> saved) onSaved,
  }) async {
    if (state.isBusy) return;
    emit(state.copyWith(status: PlanReadingStatus.saving, roomsSaved: false));
    while (_roomIds.length < rooms.length) {
      _roomIds.add(_generateId());
    }
    final saved = <Room>[];
    try {
      for (final (index, input) in rooms.indexed) {
        final room = await _repository
            .saveRoom(
              Room(
                id: _roomIds[index],
                propertyId: _property.id,
                name: input.name,
                level: input.level,
                sortOrder: existing.length + index,
                areaM2: input.areaM2,
                isMain: input.isMain && !input.isAnnex,
                isAnnex: input.isAnnex,
                source: RoomSource.plan,
              ),
            )
            .timeout(_timeout);
        saved.add(room);
        onSaved(List.unmodifiable(saved));
        if (isClosed) return;
      }
      emit(state.copyWith(status: PlanReadingStatus.idle, roomsSaved: true));
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          status: PlanReadingStatus.idle,
          notice: PlanReadingNotice.saveFailed,
        ),
      );
    }
  }

  /// The answers of a room read on the plan: its kind gives main / annex.
  static RoomInput inputOf(PlanRoom room) {
    final kind = RoomSuggestion.byKind(room.kind);
    final isAnnex = kind?.isAnnex ?? false;
    return RoomInput(
      name: room.name,
      level: room.level,
      areaM2: room.areaM2 ?? 0,
      isMain: (kind?.isMain ?? false) && !isAnnex,
      isAnnex: isAnnex,
    );
  }
}
