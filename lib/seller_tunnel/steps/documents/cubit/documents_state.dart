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

  /// Copying a document of another property failed.
  reuseFailed,

  /// The document was uploaded.
  uploaded,

  /// Deleting the document failed.
  deleteFailed,

  /// The document was deleted.
  deleted,

  /// The document could not be opened.
  openFailed,
}

/// A validated file (or the PDF of a scan), ready to upload.
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

/// A file whose upload failed, kept to retry it.
final class FailedUpload extends Equatable {
  const new({required this.file, required this.kind});

  final PickedDocument file;
  final DocumentKind kind;

  @override
  List<Object?> get props => [file, kind];
}

/// State of V7 · Le Vault documents.
final class DocumentsState extends Equatable {
  const new({
    required this.property,
    required this.documents,
    this.picking = false,
    this.uploading,
    this.busyDocumentIds = const {},
    this.failedUploads = const [],
    this.notice,
    this.noticeCount = 0,
    this.showsSubmissionErrors = false,
  });

  /// The dossier (for the computed statuses and the score).
  final Property property;

  /// The uploaded documents, oldest first.
  final List<PropertyDocument> documents;

  /// Whether a picker is open.
  final bool picking;

  /// File being uploaded, if any.
  final PickedDocument? uploading;

  /// Documents being deleted or opened.
  final Set<String> busyDocumentIds;

  /// Files whose upload failed, oldest first, to retry or discard.
  final List<FailedUpload> failedUploads;

  /// Last notice; [noticeCount] changes each time one is emitted.
  final DocumentsNotice? notice;
  final int noticeCount;

  /// Whether the documents needed to send the dossier are shown as errors
  /// (after a blocked "Envoyer").
  final bool showsSubmissionErrors;

  /// Statuses, missing count and transparency score.
  DocumentChecklist get checklist => DocumentChecklist.of(property, documents);

  bool get isUploading => uploading != null;

  /// Whether a document change is in progress (inputs are then disabled).
  bool get isBusy => picking || isUploading || busyDocumentIds.isNotEmpty;

  /// Whether the expert took the dossier over: documents can then only be
  /// opened (row level security refuses changes).
  bool get isLocked =>
      property.status != PropertyStatus.draft &&
      property.status != PropertyStatus.submitted;

  DocumentsState copyWith({
    List<PropertyDocument>? documents,
    bool? picking,
    PickedDocument? Function()? uploading,
    Set<String>? busyDocumentIds,
    List<FailedUpload>? failedUploads,
    DocumentsNotice? notice,
    bool? showsSubmissionErrors,
  }) {
    return DocumentsState(
      property: property,
      documents: documents ?? this.documents,
      picking: picking ?? this.picking,
      uploading: uploading == null ? this.uploading : uploading(),
      busyDocumentIds: busyDocumentIds ?? this.busyDocumentIds,
      failedUploads: failedUploads ?? this.failedUploads,
      notice: notice ?? this.notice,
      noticeCount: notice == null ? noticeCount : noticeCount + 1,
      showsSubmissionErrors:
          showsSubmissionErrors ?? this.showsSubmissionErrors,
    );
  }

  @override
  List<Object?> get props => [
    property,
    documents,
    picking,
    uploading,
    busyDocumentIds,
    failedUploads,
    notice,
    noticeCount,
    showsSubmissionErrors,
  ];
}
