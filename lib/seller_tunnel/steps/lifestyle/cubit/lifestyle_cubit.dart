import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:property_repository/property_repository.dart';

part 'lifestyle_state.dart';

/// Form of V6 · Cadre de vie and the persistence of its `lifestyle_items`.
///
/// [submit] saves the assets and watch points; on success the view hands
/// the saved rows and `LifestyleState.patchFor` to the tunnel cubit.
class LifestyleCubit extends Cubit<LifestyleState> {
  new({
    required this._propertyRepository,
    required Property property,
    List<LifestyleItem> items = const [],
    String Function()? newId,
    this._timeout = const Duration(seconds: 15),
  }) : _propertyId = property.id,
       _newId = newId ?? generateUuidV4,
       _saved = {for (final item in items) ?item.id: item},
       super(_initialState(property, items, newId ?? generateUuidV4));

  final PropertyRepository _propertyRepository;
  final String _propertyId;
  final String Function() _newId;
  final Duration _timeout;

  /// The rows known to be stored, by id.
  final Map<String, LifestyleItem> _saved;

  /// Ids of rows whose write was sent without an answer (failed or timed
  /// out): they may exist, so they are deleted if no longer wanted.
  final Set<String> _attempted = {};

  static LifestyleState _initialState(
    Property property,
    List<LifestyleItem> items,
    String Function() newId,
  ) {
    List<LifestyleItemDraft> drafts(LifestyleItemKind kind) => [
      for (final item in items)
        if (item.kind == kind) LifestyleItemDraft.fromItem(item, newId: newId),
    ];
    return LifestyleState(
      assets: drafts(LifestyleItemKind.asset),
      watchPoints: drafts(LifestyleItemKind.watchPoint),
      noiseLevel: property.noiseLevel,
      overlooking: property.overlooking,
      secretNote: property.secretNote ?? '',
    );
  }

  /// Applies [change] unless a submission is in progress (the form is
  /// disabled meanwhile).
  void _edit(LifestyleState Function(LifestyleState state) change) {
    if (state.isSubmitting) return;
    emit(change(state));
  }

  LifestyleState _withItems(
    LifestyleState s,
    LifestyleItemKind kind,
    List<LifestyleItemDraft> items,
  ) => switch (kind) {
    LifestyleItemKind.asset => s.copyWith(assets: items),
    LifestyleItemKind.watchPoint => s.copyWith(watchPoints: items),
  };

  /// Adds an item of [kind] (ignored when the list is full).
  void itemAdded(LifestyleItemKind kind, String label) => _edit((s) {
    if (!s.canAdd(kind)) return s;
    final draft = LifestyleItemDraft(
      id: _newId(),
      kind: kind,
      label: label.trim(),
    );
    return _withItems(s, kind, [...s.itemsOf(kind), draft]);
  });

  void itemEdited(LifestyleItemDraft item, String label) => _edit(
    (s) => _withItems(s, item.kind, [
      for (final draft in s.itemsOf(item.kind))
        if (draft.id == item.id) draft.copyWith(label: label.trim()) else draft,
    ]),
  );

  void itemRemoved(LifestyleItemDraft item) => _edit(
    (s) => _withItems(s, item.kind, [
      for (final draft in s.itemsOf(item.kind))
        if (draft.id != item.id) draft,
    ]),
  );

  void noiseLevelChanged(int level) =>
      _edit((s) => s.copyWith(noiseLevel: level.clamp(1, 10)));

  void overlookingChanged(Overlooking overlooking) =>
      _edit((s) => s.copyWith(overlooking: overlooking));

  void secretNoteChanged(String note) =>
      _edit((s) => s.copyWith(secretNote: note));

  /// "Continuer": deletes the rows no longer wanted, then writes the new
  /// and changed items (unchanged rows are not written). Each result is
  /// recorded as soon as it arrives, so a retry after a failure only
  /// writes what is left.
  Future<void> submit() async {
    if (state.isSubmitting) return;
    emit(state.copyWith(submission: LifestyleSubmission.inProgress));
    final wanted = [
      for (final (i, draft) in state.assets.indexed)
        draft.toItem(propertyId: _propertyId, sortOrder: i),
      for (final (i, draft) in state.watchPoints.indexed)
        draft.toItem(propertyId: _propertyId, sortOrder: i),
    ];
    final wantedIds = {for (final item in wanted) item.id};
    try {
      for (final id in {..._saved.keys, ..._attempted}) {
        if (wantedIds.contains(id)) continue;
        if (isClosed) return;
        await _propertyRepository.deleteLifestyleItem(id).timeout(_timeout);
        _saved.remove(id);
        _attempted.remove(id);
      }
      final saved = <LifestyleItem>[];
      for (final item in wanted) {
        final id = item.id!;
        if (_saved[id] != item) {
          if (isClosed) return;
          _attempted.add(id);
          _saved[id] = await _propertyRepository
              .saveLifestyleItem(item)
              .timeout(_timeout);
          _attempted.remove(id);
        }
        saved.add(_saved[id]!);
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          savedItems: saved,
          submission: LifestyleSubmission.success,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(submission: LifestyleSubmission.failure));
    }
  }
}
