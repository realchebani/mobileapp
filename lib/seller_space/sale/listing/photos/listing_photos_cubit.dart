import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:mobileapp/seller_tunnel/photos/view/photo_capture_page.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Loading of the listing photos.
enum ListingPhotosStatus { loading, ready, failure }

/// Something to tell the user once.
enum ListingPhotosNotice {
  /// 40 photos reached.
  limitReached,

  /// A photo could not be added (copied, read or sent).
  addFailed,

  /// Removing or reordering failed.
  changeFailed,
}

/// The photos of a listing (EPIC-08 · US-08.6).
final class ListingPhotosState extends Equatable {
  const new({
    this.status = ListingPhotosStatus.loading,
    this.photos = const [],
    this.urls = const {},
    this.adding = 0,
    this.busy = false,
    this.importing = false,
    this.notice,
    this.noticeCount = 0,
  });

  final ListingPhotosStatus status;

  /// The photos, cover first.
  final List<ListingPhoto> photos;

  /// Signed URLs by storage path.
  final Map<String, String> urls;

  /// Photos being added.
  final int adding;

  /// A removal or a reordering is in progress.
  final bool busy;

  /// The dossier photos are being copied.
  final bool importing;
  final ListingPhotosNotice? notice;
  final int noticeCount;

  int get count => photos.length + adding;

  bool get canAdd =>
      status == ListingPhotosStatus.ready &&
      count < ListingPhotosCubit.maxPhotos;

  ListingPhotosState copyWith({
    ListingPhotosStatus? status,
    List<ListingPhoto>? photos,
    Map<String, String>? urls,
    int? adding,
    bool? busy,
    bool? importing,
    ListingPhotosNotice? notice,
  }) => ListingPhotosState(
    status: status ?? this.status,
    photos: photos ?? this.photos,
    urls: urls ?? this.urls,
    adding: adding ?? this.adding,
    busy: busy ?? this.busy,
    importing: importing ?? this.importing,
    notice: notice ?? this.notice,
    noticeCount: notice == null ? noticeCount : noticeCount + 1,
  );

  @override
  List<Object?> get props => [
    status,
    photos,
    urls,
    adding,
    busy,
    importing,
    notice,
    noticeCount,
  ];
}

/// The photos of the listing of a sale: loads them; the first time, copies
/// every photo of the dossier (owner decision: all of them, persons
/// included); adds new ones (photo screen of EPIC-15, library); removes;
/// puts one first (the cover). Never the identity document nor any other
/// document: only `room_photos` are copied.
class ListingPhotosCubit extends Cubit<ListingPhotosState>
    implements PhotoCaptureTarget {
  new({
    required this._saleRepository,
    required this._propertyRepository,
    required this._processor,
    required this._sale,
    required this._ownerId,
    required this._members,
    this._onImported,
    String Function()? generateId,
    this._timeout = const Duration(seconds: 15),
  }) : _generateId = generateId ?? generateUuidV4,
       super(const ListingPhotosState());

  /// Most photos per listing (the database refuses more).
  static const maxPhotos = 40;

  static const int _unknownRoom = 1 << 20;

  /// Fewest photos to publish (plan Q11).
  static const minPhotos = 5;

  final SaleRepository _saleRepository;
  final PropertyRepository _propertyRepository;
  final PhotoProcessor _processor;
  final Sale _sale;
  final String _ownerId;
  final List<Property> _members;
  final String Function() _generateId;
  final Duration _timeout;

  /// Called once the dossier photos were imported (the sale changed).
  final void Function()? _onImported;

  Future<void> _queue = Future.value();

  /// Loads the photos, then imports the dossier photos the first time.
  Future<void> load() async {
    try {
      final photos = await _saleRepository
          .getListingPhotos(_sale.id)
          .timeout(_timeout);
      if (isClosed) return;
      emit(state.copyWith(status: ListingPhotosStatus.ready, photos: photos));
      await _loadUrls();
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: ListingPhotosStatus.failure));
      return;
    }
    if (_sale.photosImportedAt == null) await importDossierPhotos();
  }

  Future<void> _loadUrls() async {
    final missing = [
      for (final photo in state.photos)
        if (!state.urls.containsKey(photo.storagePath)) photo.storagePath,
    ];
    if (missing.isEmpty) return;
    try {
      final urls = await _saleRepository
          .listingPhotoUrls(missing)
          .timeout(_timeout);
      if (!isClosed) emit(state.copyWith(urls: {...state.urls, ...urls}));
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
    }
  }

  /// Copies the dossier photos not in the listing yet (all rooms of all the
  /// properties sold, in their order), then records the import.
  Future<void> importDossierPhotos() async {
    if (state.importing) return;
    emit(state.copyWith(importing: true));
    var failed = false;
    try {
      final copied = {
        for (final photo in state.photos) ?photo.sourceRoomPhotoId,
      };
      for (final member in _members) {
        final (rooms, photos) = await (
          _propertyRepository.getRooms(member.id),
          _propertyRepository.getRoomPhotos(member.id),
        ).wait.timeout(_timeout);
        final order = {for (final room in rooms) ?room.id: room.sortOrder};
        final names = {for (final room in rooms) ?room.id: room.name};
        final sorted = [...photos]
          ..sort((a, b) {
            // Photos of a room no longer listed come last.
            final byRoom = (order[a.roomId] ?? _unknownRoom).compareTo(
              order[b.roomId] ?? _unknownRoom,
            );
            return byRoom != 0 ? byRoom : a.sortOrder.compareTo(b.sortOrder);
          });
        for (final photo in sorted) {
          if (isClosed || copied.contains(photo.id)) continue;
          if (state.photos.length >= maxPhotos) break;
          try {
            final added = await _saleRepository
                .copyRoomPhoto(
                  _newPhoto(
                    propertyId: member.id,
                    roomId: photo.roomId,
                    sourceRoomPhotoId: photo.id,
                    width: photo.width,
                    height: photo.height,
                    sizeBytes: photo.sizeBytes,
                    caption: _caption(names[photo.roomId]),
                  ),
                  sourcePath: photo.storagePath,
                )
                .timeout(_timeout);
            if (isClosed) return;
            copied.add(photo.id);
            emit(state.copyWith(photos: [...state.photos, added]));
          } on Object catch (error, stackTrace) {
            if (isClosed) return;
            addError(error, stackTrace);
            failed = true;
          }
        }
      }
      if (!failed) {
        await _saleRepository
            .updateSale(_sale.id, {
              SaleColumns.photosImportedAt: DateTime.now()
                  .toUtc()
                  .toIso8601String(),
            })
            .timeout(_timeout);
        _onImported?.call();
      }
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      failed = true;
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        importing: false,
        notice: failed ? ListingPhotosNotice.addFailed : null,
      ),
    );
    await _loadUrls();
  }

  static String? _caption(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed;
  }

  ListingPhoto _newPhoto({
    String? propertyId,
    String? roomId,
    String? sourceRoomPhotoId,
    int? width,
    int? height,
    int? sizeBytes,
    String? caption,
  }) {
    final id = _generateId();
    return ListingPhoto(
      id: id,
      saleId: _sale.id,
      storagePath: SaleRepository.listingPhotoPath(
        ownerId: _ownerId,
        saleId: _sale.id,
        photoId: id,
      ),
      propertyId: propertyId,
      roomId: roomId,
      sourceRoomPhotoId: sourceRoomPhotoId,
      width: width,
      height: height,
      sizeBytes: sizeBytes,
      sortOrder: _nextSortOrder(),
      caption: caption,
    );
  }

  int _nextSortOrder() => state.photos.isEmpty
      ? 0
      : state.photos.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) +
            1;

  @override
  bool get canAddPhoto => state.canAdd;

  bool _reserve() {
    if (isClosed) return false;
    if (state.canAdd) return true;
    emit(state.copyWith(notice: ListingPhotosNotice.limitReached));
    return false;
  }

  @override
  void addFromCamera(ProcessedPhoto processed) {
    if (!_reserve()) return;
    emit(state.copyWith(adding: state.adding + 1));
    _enqueue(() async => processed);
  }

  /// Adds photos of the library (checked and reduced on the device).
  void addFromLibrary(List<Uint8List> raw) {
    for (final bytes in raw) {
      if (!_reserve()) return;
      emit(state.copyWith(adding: state.adding + 1));
      _enqueue(() => _processor.process(bytes));
    }
  }

  void _enqueue(Future<ProcessedPhoto> Function() process) {
    _queue = _queue.then((_) => _upload(process));
  }

  Future<void> _upload(Future<ProcessedPhoto> Function() process) async {
    if (isClosed) return;
    try {
      final processed = await process();
      final photo = _newPhoto(
        propertyId: _members.length == 1 ? _members.first.id : null,
        width: processed.width,
        height: processed.height,
        sizeBytes: processed.bytes.length,
      );
      final megabytes = (processed.bytes.length / (1024 * 1024)).ceil();
      final saved = await _saleRepository
          .uploadListingPhoto(photo, bytes: processed.bytes)
          .timeout(_timeout + const Duration(seconds: 3) * megabytes);
      if (isClosed) return;
      emit(
        state.copyWith(
          photos: [...state.photos, saved],
          adding: state.adding - 1,
        ),
      );
      await _loadUrls();
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          adding: state.adding - 1,
          notice:
              error is SaleFailure &&
                  error.reason == SaleFailureReason.photoLimitReached
              ? ListingPhotosNotice.limitReached
              : ListingPhotosNotice.addFailed,
        ),
      );
    }
  }

  /// Removes [photo] from the listing.
  Future<void> remove(ListingPhoto photo) => _change(() async {
    await _saleRepository.deleteListingPhoto(photo).timeout(_timeout);
    return [
      for (final p in state.photos)
        if (p.id != photo.id) p,
    ];
  });

  /// Puts [photo] first: it becomes the cover.
  Future<void> makeCover(ListingPhoto photo) => _change(() async {
    final order = [
      photo,
      for (final p in state.photos)
        if (p.id != photo.id) p,
    ];
    return await _saleRepository
        .reorderListingPhotos(_sale.id, [for (final p in order) p.id])
        .timeout(_timeout);
  });

  Future<void> _change(Future<List<ListingPhoto>> Function() run) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      final photos = await run();
      if (isClosed) return;
      emit(state.copyWith(photos: photos, busy: false));
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(busy: false, notice: ListingPhotosNotice.changeFailed),
      );
    }
  }
}
