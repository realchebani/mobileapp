part of 'documents_cubit.dart';

/// Something to tell the user once (a snackbar).
enum DocumentsNotice {
  /// The file is larger than [DocumentsCubit.maxFileBytes].
  fileTooLarge,

  /// The file is not a PDF, JPG, PNG or HEIC.
  unsupportedType,

  /// Access to the camera or the photos was denied.
  accessDenied,

  /// The file could not be picked or read.
  pickFailed,

  /// The upload failed.
  uploadFailed,

  /// The document was uploaded.
  uploaded,

  /// Deleting the document failed.
  deleteFailed,

  /// The document was deleted.
  deleted,

  /// The document could not be opened.
  openFailed,
}

/// A validated file, ready to upload.
final class PickedDocument extends Equatable {
  const new({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  @override
  List<Object?> get props => [fileName, mimeType, bytes.length];
}

/// State of V7 · Le Vault documents.
final class DocumentsState extends Equatable {
  const new({
    required this.property,
    required this.documents,
    this.picking = false,
    this.pending,
    this.uploading,
    this.busyDocumentIds = const {},
    this.notice,
    this.noticeCount = 0,
  });

  /// The dossier (for the computed statuses and the score).
  final Property property;

  /// The uploaded documents, oldest first.
  final List<PropertyDocument> documents;

  /// Whether a picker is open.
  final bool picking;

  /// Picked file waiting for its kind, if any.
  final PickedDocument? pending;

  /// File being uploaded, if any.
  final PickedDocument? uploading;

  /// Documents being deleted or opened.
  final Set<String> busyDocumentIds;

  /// Last notice; [noticeCount] changes each time one is emitted.
  final DocumentsNotice? notice;
  final int noticeCount;

  /// Statuses, missing count and transparency score.
  DocumentChecklist get checklist => DocumentChecklist.of(property, documents);

  bool get isUploading => uploading != null;

  /// Whether a document change is in progress (inputs are then disabled).
  bool get isBusy =>
      picking || pending != null || isUploading || busyDocumentIds.isNotEmpty;

  /// Whether the expert took the dossier over: documents can then only be
  /// opened (row level security refuses changes).
  bool get isLocked =>
      property.status != PropertyStatus.draft &&
      property.status != PropertyStatus.submitted;

  DocumentsState copyWith({
    List<PropertyDocument>? documents,
    bool? picking,
    PickedDocument? Function()? pending,
    PickedDocument? Function()? uploading,
    Set<String>? busyDocumentIds,
    DocumentsNotice? notice,
  }) {
    return DocumentsState(
      property: property,
      documents: documents ?? this.documents,
      picking: picking ?? this.picking,
      pending: pending == null ? this.pending : pending(),
      uploading: uploading == null ? this.uploading : uploading(),
      busyDocumentIds: busyDocumentIds ?? this.busyDocumentIds,
      notice: notice ?? this.notice,
      noticeCount: notice == null ? noticeCount : noticeCount + 1,
    );
  }

  @override
  List<Object?> get props => [
    property,
    documents,
    picking,
    pending,
    uploading,
    busyDocumentIds,
    notice,
    noticeCount,
  ];
}
