part of 'room_photos_cubit.dart';

/// Loading of the photos of the room.
enum RoomPhotosStatus { loading, ready, failure }

/// Something to tell the user once (a snackbar).
enum RoomPhotosNotice {
  /// 12 photos per room (or 150 per property) reached.
  limitReached,

  /// A photo could not be sent (kept to retry).
  uploadFailed,

  /// A photo could not be read.
  unreadable,

  /// Access to the camera or the photos was refused.
  accessDenied,

  /// The library could not be opened.
  pickFailed,

  /// Deleting a photo failed.
  deleteFailed,

  /// Changing the order failed.
  reorderFailed,

  /// The daily quota of the vision AI is used up.
  analysisQuota,
}

/// A photo being prepared or sent (or whose upload failed).
final class PendingPhoto extends Equatable {
  const new({
    required this.id,
    required this.preview,
    required this.source,
    this.processed,
    this.failed = false,
  });

  /// The id the photo will have.
  final String id;

  /// Bytes to show while it is sent.
  final Uint8List preview;
  final PhotoSource source;

  /// Ready to upload (null while being prepared).
  final ProcessedPhoto? processed;

  /// The upload failed: retry or discard.
  final bool failed;

  PendingPhoto copyWith({ProcessedPhoto? processed, bool? failed}) =>
      PendingPhoto(
        id: id,
        preview: processed?.bytes ?? preview,
        source: source,
        processed: processed ?? this.processed,
        failed: failed ?? this.failed,
      );

  @override
  List<Object?> get props => [id, preview.length, source, processed, failed];
}

/// The photos of one room (EPIC-15).
final class RoomPhotosState extends Equatable {
  const new({
    this.status = RoomPhotosStatus.loading,
    this.photos = const [],
    this.pending = const [],
    this.urls = const {},
    this.previews = const {},
    this.busyIds = const {},
    this.analyzing = const {},
    this.analysisFailed = const {},
    this.analysisEnabled = false,
    this.notice,
    this.noticeCount = 0,
  });

  final RoomPhotosStatus status;

  /// The photos stored, in order (the first is the main one).
  final List<RoomPhoto> photos;

  /// Photos being prepared or sent, oldest first.
  final List<PendingPhoto> pending;

  /// Signed URLs of the stored photos, by storage path.
  final Map<String, String> urls;

  /// Local bytes of the photos sent during this visit, by photo id.
  final Map<String, Uint8List> previews;

  /// Photos being deleted or moved.
  final Set<String> busyIds;

  /// Photos being analysed by the vision AI.
  final Set<String> analyzing;

  /// Photos whose analysis failed (retry possible).
  final Set<String> analysisFailed;

  /// Whether the seller accepted the vision AI.
  final bool analysisEnabled;

  /// Last notice; [noticeCount] changes each time one is emitted.
  final RoomPhotosNotice? notice;
  final int noticeCount;

  /// Photos stored plus those being sent.
  int get count => photos.length + pending.length;

  /// Whether another photo can be added ([RoomPhotosCubit.maxPhotos]).
  bool get canAdd =>
      status == RoomPhotosStatus.ready && count < RoomPhotosCubit.maxPhotos;

  /// Whether photos are being prepared or sent.
  bool get isSending => pending.any((photo) => !photo.failed);

  /// Whether a change is in progress (leaving would lose it).
  bool get isBusy => isSending || busyIds.isNotEmpty;

  RoomPhotosState copyWith({
    RoomPhotosStatus? status,
    List<RoomPhoto>? photos,
    List<PendingPhoto>? pending,
    Map<String, String>? urls,
    Map<String, Uint8List>? previews,
    Set<String>? busyIds,
    Set<String>? analyzing,
    Set<String>? analysisFailed,
    bool? analysisEnabled,
    RoomPhotosNotice? notice,
  }) {
    return RoomPhotosState(
      status: status ?? this.status,
      photos: photos ?? this.photos,
      pending: pending ?? this.pending,
      urls: urls ?? this.urls,
      previews: previews ?? this.previews,
      busyIds: busyIds ?? this.busyIds,
      analyzing: analyzing ?? this.analyzing,
      analysisFailed: analysisFailed ?? this.analysisFailed,
      analysisEnabled: analysisEnabled ?? this.analysisEnabled,
      notice: notice ?? this.notice,
      noticeCount: notice == null ? noticeCount : noticeCount + 1,
    );
  }

  @override
  List<Object?> get props => [
    status,
    photos,
    pending,
    urls,
    previews.keys.toList(),
    busyIds,
    analyzing,
    analysisFailed,
    analysisEnabled,
    notice,
    noticeCount,
  ];
}
