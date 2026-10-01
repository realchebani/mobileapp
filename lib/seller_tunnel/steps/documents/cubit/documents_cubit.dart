import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/models/document_checklist.dart';
import 'package:property_repository/property_repository.dart';

part 'documents_state.dart';

/// Opens a (signed) document URL.
typedef DocumentUrlOpener = Future<bool> Function(Uri uri);

/// V7 · Le Vault documents: picks, uploads, opens and deletes the
/// documents of the dossier.
///
/// The view reports [DocumentsState.documents] to the tunnel cubit when they
/// change, and submits the dossier through it.
class DocumentsCubit extends Cubit<DocumentsState> {
  new({
    required this._propertyRepository,
    required this._documentPicker,
    required this._openUrl,
    required Property property,
    List<PropertyDocument> documents = const [],
    this._timeout = defaultTimeout,
  }) : super(DocumentsState(property: property, documents: documents));

  /// Delay after which a write is considered failed.
  static const defaultTimeout = Duration(seconds: 15);

  /// Upload delay added per started megabyte (on top of [_timeout]).
  static const uploadTimeoutPerMegabyte = Duration(seconds: 3);

  /// Largest accepted file (the bucket limit).
  static const int maxFileBytes = 20 * 1024 * 1024;

  /// MIME types accepted by the bucket, by file extension.
  static const Map<String, String> mimeTypesByExtension = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  final PropertyRepository _propertyRepository;
  final DocumentPicker _documentPicker;
  final DocumentUrlOpener _openUrl;
  final Duration _timeout;

  /// The last file whose upload failed (its answer may have been lost).
  PickedDocument? _failedUpload;

  /// Lifetime of the URLs opening the documents.
  static const documentUrlLifetime = Duration(seconds: 120);

  /// Lets the user pick a file from [source] and checks it (size, type).
  ///
  /// A valid file is uploaded at once as a document of [kind] when given;
  /// otherwise it becomes [DocumentsState.pending] until the user tells its
  /// kind ([kindChosen]) or gives up ([pendingDiscarded]).
  Future<void> pick(DocumentSource source, {DocumentKind? kind}) async {
    if (state.isBusy || state.isLocked) return;
    emit(state.copyWith(picking: true));
    final PickedDocument? picked;
    try {
      picked = await _read(source);
    } finally {
      if (!isClosed) emit(state.copyWith(picking: false));
    }
    if (picked == null || isClosed) return;
    if (kind != null) return await _upload(picked, kind);
    emit(state.copyWith(pending: () => picked));
  }

  /// The checked file picked from [source], or null (with a notice when
  /// it is not a cancellation).
  Future<PickedDocument?> _read(DocumentSource source) async {
    try {
      final file = await _documentPicker.pick(source);
      if (file == null) return null;
      final mimeType = mimeTypeOf(file);
      if (mimeType == null) {
        _notify(DocumentsNotice.unsupportedType);
        return null;
      }
      if (await file.length() > maxFileBytes) {
        _notify(DocumentsNotice.fileTooLarge);
        return null;
      }
      return PickedDocument(
        fileName: _fileNameOf(file),
        mimeType: mimeType,
        bytes: await file.readAsBytes(),
      );
    } on DocumentAccessDenied catch (error, stackTrace) {
      addError(error, stackTrace);
      _notify(DocumentsNotice.accessDenied);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      _notify(DocumentsNotice.pickFailed);
    }
    return null;
  }

  /// Uploads the pending file as a document of [kind].
  Future<void> kindChosen(DocumentKind kind) async {
    final pending = state.pending;
    if (pending == null || state.isUploading || state.isLocked) return;
    await _upload(pending, kind);
  }

  /// Drops the pending file (its kind was not given).
  void pendingDiscarded() {
    if (!isClosed) emit(state.copyWith(pending: () => null));
  }

  /// The accepted MIME type of [file] (from its extension, else from the
  /// type the picker reported), or null when it is not accepted.
  static String? mimeTypeOf(XFile file) {
    final name = _fileNameOf(file);
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final byExtension = mimeTypesByExtension[extension];
    if (byExtension != null) return byExtension;
    final reported = file.mimeType?.toLowerCase();
    return mimeTypesByExtension.containsValue(reported) ? reported : null;
  }

  static String _fileNameOf(XFile file) {
    final name = file.name.isNotEmpty ? file.name : file.path;
    return name.split('/').last;
  }

  Future<void> _upload(PickedDocument file, DocumentKind kind) async {
    if (isClosed) return;
    emit(state.copyWith(pending: () => null, uploading: () => file));
    if (file == _failedUpload) {
      // The previous upload of this file may have succeeded after its
      // timeout: look for it before sending it again.
      final documents = await _reload();
      if (isClosed) return;
      final stored = documents?.where(
        (d) => d.fileName == file.fileName && d.sizeBytes == file.bytes.length,
      );
      if (stored != null && stored.isNotEmpty) {
        _failedUpload = null;
        emit(
          state.copyWith(
            documents: documents,
            uploading: () => null,
            notice: DocumentsNotice.uploaded,
          ),
        );
        return;
      }
    }
    final property = state.property;
    final megabytes = (file.bytes.length / (1024 * 1024)).ceil();
    try {
      final document = await _propertyRepository
          .uploadDocument(
            ownerId: property.ownerId,
            propertyId: property.id,
            kind: kind,
            fileName: file.fileName,
            bytes: file.bytes,
            mimeType: file.mimeType,
          )
          .timeout(_timeout + uploadTimeoutPerMegabyte * megabytes);
      _failedUpload = null;
      if (isClosed) return;
      emit(
        state.copyWith(
          documents: [
            for (final d in state.documents)
              if (d.id != document.id) d,
            document,
          ],
          uploading: () => null,
          notice: DocumentsNotice.uploaded,
        ),
      );
    } on Object catch (error, stackTrace) {
      _failedUpload = file;
      if (isClosed) return;
      addError(error, stackTrace);
      // The answer of an upload that succeeded may have been lost: reload
      // the list so that a retry does not add the document twice.
      final documents = await _reload();
      if (isClosed) return;
      emit(
        state.copyWith(
          documents: documents,
          uploading: () => null,
          notice: DocumentsNotice.uploadFailed,
        ),
      );
    }
  }

  /// Deletes [document] (its row and its file).
  Future<void> delete(PropertyDocument document) async {
    if (state.isBusy || state.isLocked) return;
    emit(state.copyWith(busyDocumentIds: {document.id}));
    try {
      await _propertyRepository.deleteDocument(document).timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          documents: [
            for (final d in state.documents)
              if (d.id != document.id) d,
          ],
          busyDocumentIds: const {},
          notice: DocumentsNotice.deleted,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      final documents = await _reload();
      if (isClosed) return;
      emit(
        state.copyWith(
          documents: documents,
          busyDocumentIds: const {},
          notice: DocumentsNotice.deleteFailed,
        ),
      );
    }
  }

  /// Opens [document] through a temporary signed URL.
  Future<void> open(PropertyDocument document) async {
    if (state.busyDocumentIds.contains(document.id)) return;
    emit(
      state.copyWith(busyDocumentIds: {...state.busyDocumentIds, document.id}),
    );
    var opened = false;
    try {
      final url = await _propertyRepository
          .getDocumentUrl(document.storagePath, expiresIn: documentUrlLifetime)
          .timeout(_timeout);
      opened = await _openUrl(Uri.parse(url));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        busyDocumentIds: {
          for (final id in state.busyDocumentIds)
            if (id != document.id) id,
        },
        notice: opened ? null : DocumentsNotice.openFailed,
      ),
    );
  }

  /// The documents as stored, or null when they cannot be read.
  Future<List<PropertyDocument>?> _reload() async {
    try {
      return await _propertyRepository
          .getDocuments(state.property.id)
          .timeout(_timeout);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      return null;
    }
  }

  void _notify(DocumentsNotice notice) {
    if (!isClosed) emit(state.copyWith(notice: notice));
  }
}
