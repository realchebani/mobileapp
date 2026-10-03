import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_space/vault/models/vault_contents.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

part 'vault_state.dart';

/// Shares a file (iOS share sheet: save, AirDrop, mail…).
typedef DocumentSharer = Future<void> Function(
  Uint8List bytes,
  String fileName,
  String mimeType,
);

/// C1 / V18 · the vault of one property or of a sale lot: loads its
/// documents, owners and certified valuations; adds documents at any time
/// (after sending too: they are flagged "Ajouté après l’envoi"), renames,
/// shares, opens, replaces and deletes them within the rules of the
/// database (owner decision 2026-10-03).
class VaultCubit extends Cubit<VaultState> {
  new({
    required this._propertyRepository,
    required this._valuationRepository,
    required this._documentPicker,
    required this._openUrl,
    required this._share,
    PhotoProcessor? photoProcessor,
    this._onDocumentsChanged,
    this._timeout = defaultTimeout,
  }) : _photoProcessor = photoProcessor ?? const IsolatePhotoProcessor(),
       super(const VaultState());

  static const defaultTimeout = Duration(seconds: 15);

  /// Lifetime of the URLs opening the documents.
  static const urlLifetime = Duration(minutes: 5);

  final PropertyRepository _propertyRepository;
  final ValuationRepository _valuationRepository;
  final DocumentPicker _documentPicker;
  final DocumentUrlOpener _openUrl;
  final DocumentSharer _share;
  final PhotoProcessor _photoProcessor;

  /// Told the documents of a property after each change (to keep its
  /// dossier current elsewhere in the app).
  final void Function(String propertyId, List<PropertyDocument> documents)?
  _onDocumentsChanged;
  final Duration _timeout;

  /// Shows [target], made of [properties] (one, or the members of a lot),
  /// and loads their documents.
  Future<void> show(VaultTarget target, List<Property> properties) async {
    emit(
      VaultState(
        status: VaultStatus.loading,
        target: target,
        properties: properties,
      ),
    );
    await _load();
  }

  /// Loads the shown properties again (pull to refresh, "Réessayer").
  Future<void> refresh({List<Property>? properties}) async {
    if (state.target == null) return;
    emit(
      state.copyWith(
        status: state.status == VaultStatus.success
            ? VaultStatus.success
            : VaultStatus.loading,
        properties: properties,
      ),
    );
    await _load();
  }

  Future<void> _load() async {
    final target = state.target;
    final properties = state.properties;
    try {
      final ids = [for (final property in properties) property.id];
      final results = await Future.wait([
        _propertyRepository.getDocumentsOf(ids),
        for (final id in ids) _propertyRepository.getOwners(id),
        for (final property in properties)
          if (property.status == PropertyStatus.certified)
            _valuationRepository.getLatestValuation(property.id),
      ]).timeout(_timeout);
      if (isClosed || target != state.target) return;
      final certified = [
        for (final property in properties)
          if (property.status == PropertyStatus.certified) property.id,
      ];
      emit(
        state.copyWith(
          status: VaultStatus.success,
          documents: results.first! as List<PropertyDocument>,
          owners: {
            for (final (index, id) in ids.indexed)
              id: results[1 + index]! as List<PropertyOwner>,
          },
          valuations: {
            for (final (index, id) in certified.indexed)
              if (results[1 + ids.length + index] case final Valuation v) id: v,
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed || target != state.target) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: VaultStatus.failure));
    }
  }

  /// Lets the user pick a file from [source] and adds it to [target]
  /// (replacing [replacing] when given), see [add].
  Future<void> pickAndAdd(
    VaultAddTarget target,
    DocumentSource source, {
    PropertyDocument? replacing,
  }) async {
    final file = await _pickFile(source);
    if (file != null && !isClosed) {
      await add(target, file, replacing: replacing);
    }
  }

  /// The file picked from [source] (checked: type, size, image metadata
  /// removed); null when cancelled or refused (with a notice).
  Future<PickedDocument?> _pickFile(DocumentSource source) async {
    if (state.busy) return null;
    emit(state.copyWith(busy: true));
    try {
      final file = await _documentPicker.pick(source);
      if (file == null) return null;
      final mimeType = DocumentsCubit.mimeTypeOf(file);
      if (mimeType == null) {
        _notify(VaultNotice.unsupportedType);
        return null;
      }
      if (await file.length() > DocumentsCubit.maxFileBytes) {
        _notify(VaultNotice.fileTooLarge);
        return null;
      }
      var bytes = await file.readAsBytes();
      if (mimeType != 'application/pdf') {
        try {
          bytes = await _photoProcessor.stripMetadata(bytes);
        } on FormatException catch (error, stackTrace) {
          addError(error, stackTrace);
          _notify(VaultNotice.metadataUnremovable);
          return null;
        }
      }
      final name = file.name.isNotEmpty ? file.name : file.path;
      return PickedDocument(
        fileName: name.split('/').last,
        mimeType: mimeType,
        bytes: bytes,
      );
    } on DocumentAccessDenied catch (error, stackTrace) {
      addError(error, stackTrace);
      _notify(VaultNotice.accessDenied);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      _notify(VaultNotice.pickFailed);
    } finally {
      if (!isClosed) emit(state.copyWith(busy: false));
    }
    return null;
  }

  /// Uploads [file] as a new document of [target]; with [replacing], the
  /// new document replaces it (a draft's or an unverified addition is then
  /// deleted, a rejected one stays for the expert, crossed out).
  Future<void> add(
    VaultAddTarget target,
    PickedDocument file, {
    PropertyDocument? replacing,
  }) async {
    if (state.busy) await stream.firstWhere((state) => !state.busy);
    if (isClosed) return;
    final property = state.propertyById(target.propertyId);
    if (property == null) return;
    emit(state.copyWith(busy: true, failedUpload: () => null));
    final failed = VaultFailedUpload(
      target: target,
      file: file,
      replacing: replacing,
    );
    final megabytes = (file.bytes.length / (1024 * 1024)).ceil();
    PropertyDocument document;
    try {
      document = await _propertyRepository
          .uploadDocument(
            ownerId: property.ownerId,
            propertyId: property.id,
            kind: target.kind,
            fileName: file.fileName,
            bytes: file.bytes,
            mimeType: file.mimeType,
            title: replacing?.title,
            ownerRef: target.ownerRef,
          )
          .timeout(
            _timeout + DocumentsCubit.uploadTimeoutPerMegabyte * megabytes,
          );
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      // The answer of an upload that succeeded may have been lost.
      final stored = await _reloadDocuments(property.id);
      final found = stored?.where(
        (d) =>
            d.fileName == file.fileName &&
            d.sizeBytes == file.bytes.length &&
            d.kind == target.kind &&
            !state.documents.any((known) => known.id == d.id),
      );
      if (isClosed) return;
      if (found == null || found.isEmpty) {
        emit(
          state.copyWith(
            busy: false,
            failedUpload: () => failed,
            notice: () => VaultNotice.uploadFailed,
          ),
        );
        return;
      }
      document = found.first;
    }
    if (isClosed) return;
    _setDocuments(property.id, [
      for (final d in state.documents)
        if (d.id != document.id) d,
      document,
    ]);
    if (replacing != null) {
      await _replace(property, replacing, document);
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        busy: false,
        notice: () =>
            replacing == null ? VaultNotice.uploaded : VaultNotice.replaced,
      ),
    );
  }

  Future<void> _replace(
    Property property,
    PropertyDocument old,
    PropertyDocument replacement,
  ) async {
    try {
      final entry = VaultDocumentEntry(property: property, document: old);
      if (property.status != PropertyStatus.draft) {
        await _propertyRepository
            .replaceDocument(oldId: old.id, newId: replacement.id)
            .timeout(_timeout);
      }
      if (entry.canDelete) {
        await _propertyRepository.deleteDocument(old).timeout(_timeout);
        if (isClosed) return;
        _setDocuments(property.id, [
          for (final d in state.documents)
            if (d.id != old.id) d,
        ]);
      } else {
        if (isClosed) return;
        _setDocuments(property.id, [
          for (final d in state.documents)
            if (d.id == old.id) d.replacedWith(replacement.id) else d,
        ]);
      }
    } on Object catch (error, stackTrace) {
      // The new document is kept; the old one stays listed.
      addError(error, stackTrace);
    }
  }

  /// Uploads again the file of the last failed upload ("Réessayer").
  Future<void> retryUpload() async {
    final failed = state.failedUpload;
    if (failed == null) return;
    await add(failed.target, failed.file, replacing: failed.replacing);
  }

  /// Gives up the last failed upload.
  void discardFailedUpload() => emit(state.copyWith(failedUpload: () => null));

  /// Copies [source], a document of another property, into [target].
  Future<void> reuse(VaultAddTarget target, PropertyDocument source) async {
    final property = state.propertyById(target.propertyId);
    if (property == null || state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      final copy = await _propertyRepository
          .copyDocument(
            source,
            ownerId: property.ownerId,
            toPropertyId: property.id,
          )
          .timeout(_timeout);
      if (isClosed) return;
      _setDocuments(property.id, [...state.documents, copy]);
      emit(state.copyWith(busy: false, notice: () => VaultNotice.uploaded));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      final stored = await _reloadDocuments(property.id);
      if (isClosed) return;
      if (stored != null) _setDocuments(property.id, stored);
      emit(state.copyWith(busy: false, notice: () => VaultNotice.reuseFailed));
    }
  }

  /// Renames [document] ([title] empty: the label of its kind).
  Future<void> rename(PropertyDocument document, String title) =>
      _change(document, () async {
        final saved = await _propertyRepository
            .renameDocument(document.id, title)
            .timeout(_timeout);
        return [
          for (final d in state.documents)
            if (d.id == document.id) d.withTitle(saved.title) else d,
        ];
      });

  /// Saves who may see [document] later.
  Future<void> setVisibility(
    PropertyDocument document,
    Set<DocumentVisibility> visibility,
  ) => _change(document, () async {
    final saved = await _propertyRepository
        .setDocumentVisibility(document.id, visibility)
        .timeout(_timeout);
    return [
      for (final d in state.documents)
        if (d.id == document.id) d.withVisibility(saved) else d,
    ];
  });

  /// Deletes [document] (a draft's, or an unverified addition).
  Future<void> delete(PropertyDocument document) async {
    final property = state.propertyById(document.propertyId);
    if (property == null) return;
    final ok = await _change(document, () async {
      await _propertyRepository.deleteDocument(document).timeout(_timeout);
      return [
        for (final d in state.documents)
          if (d.id != document.id) d,
      ];
    }, failure: VaultNotice.deleteFailed);
    if (ok && !isClosed) {
      emit(state.copyWith(notice: () => VaultNotice.deleted));
    }
  }

  /// Runs [write] for [document] and records the documents it returns;
  /// false (with [failure], after reloading the documents) on error.
  Future<bool> _change(
    PropertyDocument document,
    Future<List<PropertyDocument>> Function() write, {
    VaultNotice failure = VaultNotice.saveFailed,
  }) async {
    if (state.busyDocumentIds.contains(document.id)) return false;
    _setBusy(document.id, busy: true);
    try {
      final documents = await write();
      if (isClosed) return false;
      _setDocuments(document.propertyId, documents);
      _setBusy(document.id, busy: false);
      return true;
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      final stored = await _reloadDocuments(document.propertyId);
      if (isClosed) return false;
      if (stored != null) _setDocuments(document.propertyId, stored);
      _setBusy(document.id, busy: false);
      _notify(failure);
      return false;
    }
  }

  /// Opens [document] through a temporary signed URL.
  Future<void> open(PropertyDocument document) =>
      _deliver(document.id, () async {
        final url = await _propertyRepository
            .getDocumentUrl(document.storagePath, expiresIn: urlLifetime)
            .timeout(_timeout);
        return await _openUrl(Uri.parse(url));
      }, failure: VaultNotice.openFailed);

  /// Opens the PDF report of [valuation].
  Future<void> openReport(Valuation valuation) =>
      _deliver(valuation.id, () async {
        final url = await _valuationRepository
            .getReportUrl(valuation.reportStoragePath!, expiresIn: urlLifetime)
            .timeout(_timeout);
        return await _openUrl(Uri.parse(url));
      }, failure: VaultNotice.openFailed);

  /// Downloads [document] and shares it ("Télécharger").
  Future<void> share(PropertyDocument document) =>
      _deliver(document.id, () async {
        final bytes = await _propertyRepository
            .downloadDocument(document.storagePath)
            .timeout(_timeout * 2);
        await _share(
          bytes,
          document.fileName ?? document.storagePath.split('/').last,
          document.mimeType ?? 'application/octet-stream',
        );
        return true;
      }, failure: VaultNotice.shareFailed);

  Future<void> _deliver(
    String id,
    Future<bool> Function() run, {
    required VaultNotice failure,
  }) async {
    if (state.busyDocumentIds.contains(id)) return;
    _setBusy(id, busy: true);
    var done = false;
    try {
      done = await run();
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
    }
    if (isClosed) return;
    _setBusy(id, busy: false);
    if (!done) _notify(failure);
  }

  /// The notice was shown.
  void noticeShown() => emit(state.copyWith(notice: () => null));

  void _setBusy(String id, {required bool busy}) => emit(
    state.copyWith(
      busyDocumentIds: busy
          ? {...state.busyDocumentIds, id}
          : {
              for (final other in state.busyDocumentIds)
                if (other != id) other,
            },
    ),
  );

  void _setDocuments(String propertyId, List<PropertyDocument> documents) {
    final merged = [
      for (final d in state.documents)
        if (d.propertyId != propertyId) d,
      for (final d in documents)
        if (d.propertyId == propertyId) d,
    ];
    emit(state.copyWith(documents: merged));
    _onDocumentsChanged?.call(propertyId, [
      for (final d in merged)
        if (d.propertyId == propertyId) d,
    ]);
  }

  Future<List<PropertyDocument>?> _reloadDocuments(String propertyId) async {
    try {
      return await _propertyRepository
          .getDocuments(propertyId)
          .timeout(_timeout);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      return null;
    }
  }

  void _notify(VaultNotice notice) {
    if (!isClosed) emit(state.copyWith(notice: () => notice));
  }
}
