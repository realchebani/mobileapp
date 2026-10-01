part of 'document_scan_cubit.dart';

/// What the scanning session is doing.
enum DocumentScanStatus {
  /// Waiting for the user (pages to review, add, reorder or delete).
  idle,

  /// The scanner (or the camera) is open.
  capturing,

  /// The PDF is being made.
  building,

  /// The PDF is ready: [DocumentScanState.result].
  done,
}

/// Something to tell the user once.
enum DocumentScanNotice {
  /// Access to the camera was denied.
  accessDenied,

  /// The scanner failed.
  captureFailed,

  /// Pages beyond [DocumentScanCubit.maxPages] were dropped.
  truncated,

  /// The pages do not fit in 20 MB, even compressed.
  tooLarge,

  /// The PDF could not be made (unreadable page…).
  buildFailed,
}

/// A scanned page.
final class ScannedPage extends Equatable {
  const new({required this.id, required this.bytes});

  /// Unique within the session (stable across reorders).
  final int id;

  /// The image (JPEG, or PNG/HEIC from the camera fallback).
  final Uint8List bytes;

  @override
  List<Object?> get props => [id];
}

/// State of a multi-page scanning session.
final class DocumentScanState extends Equatable {
  const new({
    this.pages = const [],
    this.status = DocumentScanStatus.idle,
    this.captures = 0,
    this.notice,
    this.noticeCount = 0,
    this.result,
  });

  /// The pages, in the order of the PDF.
  final List<ScannedPage> pages;

  final DocumentScanStatus status;

  /// Number of finished captures (cancelled or not).
  final int captures;

  /// Last notice; [noticeCount] changes each time one is emitted.
  final DocumentScanNotice? notice;
  final int noticeCount;

  /// The PDF of the pages, once [DocumentScanStatus.done].
  final PickedDocument? result;

  /// Whether the scanner is open or the PDF is being made.
  bool get isBusy => status != DocumentScanStatus.idle;

  /// Whether no more pages can be added.
  bool get isFull => pages.length >= DocumentScanCubit.maxPages;

  DocumentScanState copyWith({
    List<ScannedPage>? pages,
    DocumentScanStatus? status,
    int? captures,
    DocumentScanNotice? notice,
    PickedDocument? result,
  }) {
    return DocumentScanState(
      pages: pages ?? this.pages,
      status: status ?? this.status,
      captures: captures ?? this.captures,
      notice: notice ?? this.notice,
      noticeCount: notice == null ? noticeCount : noticeCount + 1,
      result: result ?? this.result,
    );
  }

  @override
  List<Object?> get props => [
    pages,
    status,
    captures,
    notice,
    noticeCount,
    result,
  ];
}
