import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:property_repository/property_repository.dart';

part 'room_photos_state.dart';

/// The photos of one room (EPIC-15): load, add (camera or library, checked
/// and reduced on the device), send in the background, delete, put first,
/// and the analysis of the vision AI when the seller accepted it.
///
/// Independent of the seller tunnel (only ids): the listing (V11a,
/// EPIC-08) can reuse it.
class RoomPhotosCubit extends Cubit<RoomPhotosState> {
  new({
    required this._repository,
    required this._processor,
    required this._ownerId,
    required this._propertyId,
    required this._roomId,
    bool analysisEnabled = false,
    String Function()? generateId,
    DateTime Function()? now,
    this._timeout = defaultTimeout,
  }) : _generateId = generateId ?? generateUuidV4,
       _now = now ?? DateTime.now,
       super(RoomPhotosState(analysisEnabled: analysisEnabled));

  /// Most photos per room (the database refuses more).
  static const maxPhotos = 12;

  /// Delay after which a write is considered failed.
  static const defaultTimeout = Duration(seconds: 15);

  /// Upload delay added per started megabyte.
  static const uploadTimeoutPerMegabyte = Duration(seconds: 3);

  /// Delay of an analysis by the vision AI.
  static const analysisTimeout = Duration(seconds: 60);

  final PropertyRepository _repository;
  final PhotoProcessor _processor;
  final String _ownerId;
  final String _propertyId;
  final String _roomId;
  final String Function() _generateId;
  final DateTime Function() _now;
  final Duration _timeout;

  /// Uploads run one after the other, in the order the photos were added.
  Future<void> _uploads = Future.value();

  /// Analyses run one after the other.
  Future<void> _analyses = Future.value();

  /// The quota of the vision AI is used up: no more analyses this visit.
  bool _quotaReached = false;

  /// Loads the photos of the room and their URLs; analyses those not yet
  /// analysed when the vision AI is accepted.
  Future<void> load() async {
    emit(state.copyWith(status: RoomPhotosStatus.loading));
    try {
      final photos = await _repository
          .getRoomPhotos(_propertyId, roomId: _roomId)
          .timeout(_timeout);
      if (isClosed) return;
      emit(state.copyWith(status: RoomPhotosStatus.ready, photos: photos));
      await _loadUrls(photos);
      _analyzeMissing();
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: RoomPhotosStatus.failure));
    }
  }

  Future<void> _loadUrls(List<RoomPhoto> photos) async {
    final missing = [
      for (final photo in photos)
        if (!state.urls.containsKey(photo.storagePath)) photo.storagePath,
    ];
    if (missing.isEmpty) return;
    try {
      final urls = await _repository.getPhotoUrls(missing).timeout(_timeout);
      if (isClosed) return;
      emit(state.copyWith(urls: {...state.urls, ...urls}));
    } on Object catch (error, stackTrace) {
      // The thumbnails then show a placeholder.
      if (!isClosed) addError(error, stackTrace);
    }
  }

  /// Adds photos of the library ([raw] images): each is checked, reduced
  /// and sent in the background. Photos beyond [maxPhotos] are dropped
  /// (with a notice).
  void addFromLibrary(List<Uint8List> raw) {
    for (final bytes in raw) {
      if (!_reserveSlot()) return;
      final pending = PendingPhoto(
        id: _generateId(),
        preview: bytes,
        source: PhotoSource.library,
      );
      emit(state.copyWith(pending: [...state.pending, pending]));
      _enqueue(pending.id, () => _processor.process(bytes));
    }
  }

  /// Adds a photo of the camera, already checked and reduced by the photo
  /// screen.
  void addFromCamera(ProcessedPhoto processed) {
    if (!_reserveSlot()) return;
    final pending = PendingPhoto(
      id: _generateId(),
      preview: processed.bytes,
      source: PhotoSource.camera,
      processed: processed,
    );
    emit(state.copyWith(pending: [...state.pending, pending]));
    _enqueue(pending.id, null);
  }

  bool _reserveSlot() {
    if (isClosed) return false;
    if (state.canAdd) return true;
    emit(state.copyWith(notice: RoomPhotosNotice.limitReached));
    return false;
  }

  /// Sends again the photo [id] whose upload failed.
  void retry(String id) {
    final pending = _pending(id);
    if (pending == null || !pending.failed) return;
    _replacePending(pending.copyWith(failed: false));
    _enqueue(id, null);
  }

  /// Gives up the photo [id] whose upload failed; its row and file are
  /// deleted in case the upload succeeded after all (lost answer).
  void discard(String id) {
    if (_pending(id)?.failed != true) return;
    unawaited(_repository.discardRoomPhoto(_photoOf(id)));
    emit(
      state.copyWith(
        pending: [
          for (final p in state.pending)
            if (p.id != id) p,
        ],
      ),
    );
  }

  PendingPhoto? _pending(String id) {
    for (final pending in state.pending) {
      if (pending.id == id) return pending;
    }
    return null;
  }

  void _replacePending(PendingPhoto pending) => emit(
    state.copyWith(
      pending: [
        for (final p in state.pending)
          if (p.id == pending.id) pending else p,
      ],
    ),
  );

  void _enqueue(String id, Future<ProcessedPhoto> Function()? process) {
    _uploads = _uploads.then((_) => _send(id, process));
  }

  Future<void> _send(
    String id,
    Future<ProcessedPhoto> Function()? process,
  ) async {
    if (isClosed) return;
    var pending = _pending(id);
    if (pending == null) return;
    if (process != null) {
      try {
        final processed = await process();
        if (isClosed) return;
        pending = pending.copyWith(processed: processed);
        _replacePending(pending);
      } on Object catch (error, stackTrace) {
        if (isClosed) return;
        addError(error, stackTrace);
        emit(
          state.copyWith(
            pending: [
              for (final p in state.pending)
                if (p.id != id) p,
            ],
            notice: RoomPhotosNotice.unreadable,
          ),
        );
        return;
      }
    }
    final processed = pending.processed!;
    final photo = _photoOf(
      id,
      width: processed.width,
      height: processed.height,
      sizeBytes: processed.bytes.length,
      sortOrder: _nextSortOrder(),
      source: pending.source,
      quality: processed.quality,
      takenAt: _now(),
    );
    final megabytes = (processed.bytes.length / (1024 * 1024)).ceil();
    try {
      final saved = await _repository
          .uploadRoomPhoto(photo, bytes: processed.bytes)
          .timeout(_timeout + uploadTimeoutPerMegabyte * megabytes);
      if (isClosed) return;
      emit(
        state.copyWith(
          photos: [...state.photos, saved],
          previews: {...state.previews, saved.id: processed.bytes},
          pending: [
            for (final p in state.pending)
              if (p.id != id) p,
          ],
        ),
      );
      if (state.analysisEnabled) _enqueueAnalysis(saved);
    } on RoomPhotoLimitFailure catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          pending: [
            for (final p in state.pending)
              if (p.id != id) p,
          ],
          notice: RoomPhotosNotice.limitReached,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      // The answer may have been lost (timeout): the photo is then stored.
      final stored = await _stored(id);
      if (isClosed) return;
      if (stored != null) {
        emit(
          state.copyWith(
            photos: [...state.photos, stored],
            previews: {...state.previews, id: processed.bytes},
            pending: [
              for (final p in state.pending)
                if (p.id != id) p,
            ],
          ),
        );
        if (state.analysisEnabled) _enqueueAnalysis(stored);
        return;
      }
      final current = _pending(id);
      if (current != null) _replacePending(current.copyWith(failed: true));
      emit(state.copyWith(notice: RoomPhotosNotice.uploadFailed));
    }
  }

  /// The photo [id] as stored, or null (not stored, or unknown).
  Future<RoomPhoto?> _stored(String id) async {
    try {
      final photos = await _repository
          .getRoomPhotos(_propertyId, roomId: _roomId)
          .timeout(_timeout);
      return photos.where((photo) => photo.id == id).firstOrNull;
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      return null;
    }
  }

  RoomPhoto _photoOf(
    String id, {
    int? width,
    int? height,
    int? sizeBytes,
    int sortOrder = 0,
    PhotoSource source = PhotoSource.camera,
    PhotoQuality? quality,
    DateTime? takenAt,
  }) => RoomPhoto(
    id: id,
    propertyId: _propertyId,
    roomId: _roomId,
    storagePath: PropertyRepository.roomPhotoPath(
      ownerId: _ownerId,
      propertyId: _propertyId,
      roomId: _roomId,
      photoId: id,
    ),
    width: width,
    height: height,
    sizeBytes: sizeBytes,
    sortOrder: sortOrder,
    source: source,
    quality: quality,
    takenAt: takenAt,
  );

  int _nextSortOrder() => state.photos.isEmpty
      ? 0
      : state.photos.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) +
            1;

  /// Deletes [photo] (its row and its file).
  Future<void> delete(RoomPhoto photo) async {
    if (state.busyIds.contains(photo.id)) return;
    emit(state.copyWith(busyIds: {...state.busyIds, photo.id}));
    try {
      await _repository.deleteRoomPhoto(photo).timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          photos: [
            for (final p in state.photos)
              if (p.id != photo.id) p,
          ],
          busyIds: {...state.busyIds}..remove(photo.id),
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          busyIds: {...state.busyIds}..remove(photo.id),
          notice: RoomPhotosNotice.deleteFailed,
        ),
      );
    }
  }

  /// Puts [photo] first (the main photo of the room).
  Future<void> moveFirst(RoomPhoto photo) async {
    if (state.busyIds.isNotEmpty || state.photos.first.id == photo.id) return;
    final order = [
      photo,
      for (final p in state.photos)
        if (p.id != photo.id) p,
    ];
    emit(state.copyWith(busyIds: {for (final p in order) p.id}));
    try {
      final saved = await _repository
          .reorderRoomPhotos(order)
          .timeout(_timeout);
      if (isClosed) return;
      emit(state.copyWith(photos: saved, busyIds: const {}));
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          busyIds: const {},
          notice: RoomPhotosNotice.reorderFailed,
        ),
      );
    }
  }

  /// The seller accepted the vision AI: analyses the photos not analysed
  /// yet.
  void enableAnalysis() {
    if (isClosed || state.analysisEnabled) return;
    emit(state.copyWith(analysisEnabled: true));
    _analyzeMissing();
  }

  /// The seller withdrew the consent: no more photo is sent to the vision
  /// AI (the analyses already stored stay for the expert).
  void disableAnalysis() {
    if (isClosed || !state.analysisEnabled) return;
    emit(
      state.copyWith(
        analysisEnabled: false,
        analyzing: const {},
        analysisFailed: const {},
      ),
    );
  }

  /// Analyses again the photo [id] whose analysis failed.
  void retryAnalysis(String id) {
    final photo = state.photos.where((p) => p.id == id).firstOrNull;
    if (photo == null || !state.analysisFailed.contains(id)) return;
    _quotaReached = false;
    emit(state.copyWith(analysisFailed: {...state.analysisFailed}..remove(id)));
    _enqueueAnalysis(photo);
  }

  void _analyzeMissing() {
    if (!state.analysisEnabled) return;
    for (final photo in state.photos) {
      if (photo.analysis == null && !state.analysisFailed.contains(photo.id)) {
        _enqueueAnalysis(photo);
      }
    }
  }

  void _enqueueAnalysis(RoomPhoto photo) {
    if (state.analyzing.contains(photo.id)) return;
    emit(state.copyWith(analyzing: {...state.analyzing, photo.id}));
    _analyses = _analyses.then((_) => _analyze(photo.id));
  }

  Future<void> _analyze(String id) async {
    if (isClosed) return;
    final done = {...state.analyzing}..remove(id);
    if (!state.analysisEnabled) return;
    if (_quotaReached || !state.photos.any((p) => p.id == id)) {
      emit(
        state.copyWith(
          analyzing: done,
          analysisFailed: _quotaReached
              ? {...state.analysisFailed, id}
              : state.analysisFailed,
        ),
      );
      return;
    }
    try {
      final analysis = await _repository
          .analyzeRoomPhoto(id)
          .timeout(analysisTimeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          photos: [
            for (final p in state.photos)
              if (p.id == id) p.withAnalysis(analysis) else p,
          ],
          analyzing: {...state.analyzing}..remove(id),
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      final quota = error is VisionQuotaFailure;
      if (quota) _quotaReached = true;
      emit(
        state.copyWith(
          analyzing: {...state.analyzing}..remove(id),
          analysisFailed: {...state.analysisFailed, id},
          notice: quota ? RoomPhotosNotice.analysisQuota : null,
        ),
      );
    }
  }
}
