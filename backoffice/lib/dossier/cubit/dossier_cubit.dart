import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'dossier_state.dart';

/// One dossier: loaded with `bo_get_dossier` (journaled), its actions, and
/// the signed URLs of its files.
class DossierCubit extends Cubit<DossierState> {
  new({required this._repository, required this.propertyId})
    : super(const DossierState());

  final BackOfficeRepository _repository;
  final String propertyId;

  /// Files signed per call (bo-files accepts 60).
  static const signBatch = 60;

  Future<void> load() async {
    try {
      final dossier = await _repository.getDossier(propertyId);
      emit(state.copyWith(load: DossierLoad.ready, dossier: dossier));
    } on Object {
      emit(state.copyWith(load: DossierLoad.failure));
      rethrow;
    }
  }

  /// Runs [action] then reloads the dossier.
  Future<void> _act(Future<void> Function() action) async {
    emit(state.copyWith(busy: true));
    try {
      await action();
      await load();
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  Future<void> startReview() => _act(() => _repository.startReview(propertyId));

  Future<void> verifyDocument(String documentId) =>
      _act(() => _repository.verifyDocument(documentId));

  Future<void> rejectDocument(String documentId, String reason) =>
      _act(() => _repository.rejectDocument(documentId, reason));

  Future<void> verifyIdentity(String ownerId) =>
      _act(() => _repository.verifyIdentity(ownerId));

  /// A short-lived URL of one file (journaled).
  Future<String> signFile(FileRequest file) async {
    final signed = await _repository.signFiles(propertyId, [file]);
    return signed.single.url;
  }

  /// Signs every photo of the dossier not signed yet.
  Future<void> loadPhotos() async {
    final dossier = state.dossier;
    if (dossier == null) return;
    final missing = [
      for (final photo in dossier.photos)
        if (!state.photoUrls.containsKey(photo.id)) photo.id,
    ];
    final urls = {...state.photoUrls};
    for (var i = 0; i < missing.length; i += signBatch) {
      final batch = missing.skip(i).take(signBatch);
      final signed = await _repository.signFiles(propertyId, [
        for (final id in batch) FileRequest(FileKind.photo, id),
      ]);
      for (final file in signed) {
        urls[file.id] = file.url;
      }
      emit(state.copyWith(photoUrls: {...urls}));
    }
  }

  /// Forgets the photo URLs (they expire after 5 minutes).
  void clearPhotoUrls() => emit(state.copyWith(photoUrls: const {}));

  Future<void> loadAudit() async {
    final entries = await _repository.audit(propertyId: propertyId);
    emit(state.copyWith(audit: entries));
  }
}
