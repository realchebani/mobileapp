import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_form.dart';
import 'package:property_repository/property_repository.dart';

part 'lifestyle_state.dart';

/// Form of V6 · Cadre de vie and the persistence of its `lifestyle_items`.
///
/// [submit] saves the assets and watch points; on success the view hands
/// the saved rows and `LifestyleState.patchFor` to the tunnel cubit.
class LifestyleCubit extends Cubit<LifestyleState>
    with VoiceFormMixin<LifestyleState> {
  new({
    required this._propertyRepository,
    required Property property,
    List<LifestyleItem> items = const [],
    List<PendingAnswer> pendingItems = const [],
    String Function()? newId,
    DateTime Function()? clock,
    this._timeout = const Duration(seconds: 15),
  }) : _propertyId = property.id,
       _newId = newId ?? generateUuidV4,
       _clock = clock ?? DateTime.now,
       _saved = {for (final item in items) ?item.id: item},
       _pending = {for (final answer in pendingItems) answer.id: answer},
       super(
         _initialState(property, items, pendingItems, newId ?? generateUuidV4),
       );

  final DateTime Function() _clock;

  /// Items said on another step (EPIC-16), by pending answer id.
  final Map<String, PendingAnswer> _pending;

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
    List<PendingAnswer> pending,
    String Function() newId,
  ) {
    List<LifestyleItemDraft> drafts(LifestyleItemKind kind) => [
      for (final item in items)
        if (item.kind == kind) LifestyleItemDraft.fromItem(item, newId: newId),
      // Said on another step: « À confirmer », within the limits.
      for (final answer in pending)
        if (_pendingDraft(answer, newId) case final draft?
            when draft.kind == kind)
          draft,
    ].take(lifestyleItemsMax).toList();
    return LifestyleState(
      assets: drafts(LifestyleItemKind.asset),
      watchPoints: drafts(LifestyleItemKind.watchPoint),
      noiseLevel: property.noiseLevel,
      overlooking: property.overlooking,
      secretNote: property.secretNote ?? '',
    );
  }

  static LifestyleItemDraft? _pendingDraft(
    PendingAnswer answer,
    String Function() newId,
  ) {
    final values = answer.values;
    final label = values['label'];
    if (label is! String || !isValidLifestyleLabel(label)) return null;
    return LifestyleItemDraft(
      id: newId(),
      kind: values['kind'] == 'watch_point'
          ? LifestyleItemKind.watchPoint
          : LifestyleItemKind.asset,
      label: label.trim(),
      source: LifestyleItemSource.voice,
      pendingId: answer.id,
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

  @override
  bool get acceptsVoice => !state.isSubmitting;

  @override
  AgentTurnContext get voiceContext => AgentTurnContext(
    draft: {
      PropertyColumns.noiseLevel: state.noiseLevel,
      PropertyColumns.overlooking: state.overlooking?.value,
    },
  );

  /// Adds what the voice agent understood (V6 "Parlez librement"): the
  /// items (source "voix", within the limits), the noise and overlooking
  /// it heard, and a secret note as a suggestion only. Nothing is saved
  /// before "Continuer".
  @override
  LifestyleState applyVoiceTurn(LifestyleState state, AgentTurn turn) {
    var next = state;
    final [turnId, ...confirmation] = turn.turnId.split('#');
    for (final (index, item) in turn.lifestyleItems.indexed) {
      final kind = item.isAsset
          ? LifestyleItemKind.asset
          : LifestyleItemKind.watchPoint;
      final label = item.label.trim();
      final known = next
          .itemsOf(kind)
          .any((draft) => draft.label.toLowerCase() == label.toLowerCase());
      if (known || !next.canAdd(kind) || !isValidLifestyleLabel(label)) {
        continue;
      }
      next = _withItems(next, kind, [
        ...next.itemsOf(kind),
        LifestyleItemDraft(
          id: _newId(),
          kind: kind,
          label: label,
          source: LifestyleItemSource.voice,
          // EPIC-16: the words it comes from (journal evidence `li:<i>`).
          fieldSources: {
            'label': FieldSource(
              kind: FieldSourceKind.dictated,
              at: _clock(),
              turnId: turnId,
              evidenceKey: [...confirmation, 'li:$index'].join('.'),
            ).toJson(),
          },
        ),
      ]);
    }
    final dictated = {...next.dictated};
    final noise = turn.patch[PropertyColumns.noiseLevel];
    if (noise is num) {
      next = next.copyWith(noiseLevel: noise.toInt().clamp(1, 10));
      dictated.add(PropertyColumns.noiseLevel);
    }
    final overlooking = parseDbEnum(
      Overlooking.values,
      turn.patch[PropertyColumns.overlooking],
    );
    if (overlooking != null) {
      next = next.copyWith(overlooking: overlooking);
      dictated.add(PropertyColumns.overlooking);
    }
    final note = turn.suggestions[PropertyColumns.secretNote]?.trim();
    if (note != null && note.isNotEmpty) {
      next = next.copyWith(secretNoteSuggestion: () => note);
    }
    return next.copyWith(dictated: dictated);
  }

  /// [draft] with the origin of its label: kept when already recorded,
  /// said on another step (pending, as said), or typed (new or changed).
  LifestyleItemDraft _traced(LifestyleItemDraft draft, Set<String> confirmed) {
    if (draft.fieldSources.isNotEmpty) return draft;
    final saved = _saved[draft.id];
    if (saved != null && saved.label == draft.label) {
      return draft.withSources(saved.fieldSources);
    }
    final answer = _pending[draft.pendingId];
    final now = _clock();
    final source =
        answer != null && draft.label == '${answer.values['label']}'.trim()
        ? FieldSource(
            kind: FieldSourceKind.dictatedElsewhere,
            at: now,
            turnId: answer.turnId,
            pendingId: answer.id,
            confirmation: confirmed.contains(answer.id)
                ? FieldConfirmation.yes
                : FieldConfirmation.continueTapped,
          )
        : FieldSource.typed(now);
    return draft.withSources({'label': source.toJson()});
  }

  /// Uses the suggested secret note (appended to the current note).
  void secretNoteSuggestionUsed() => _edit((s) {
    final suggestion = s.secretNoteSuggestion;
    if (suggestion == null) return s;
    final current = s.secretNote.trim();
    final note = current.isEmpty ? suggestion : '$current\n$suggestion';
    return s.copyWith(
      secretNote: String.fromCharCodes(note.runes.take(secretNoteMaxLength)),
      secretNoteSuggestion: () => null,
    );
  });

  void secretNoteSuggestionDismissed() =>
      _edit((s) => s.copyWith(secretNoteSuggestion: () => null));

  /// "Continuer": deletes the rows no longer wanted, then writes the new
  /// and changed items (unchanged rows are not written). Each result is
  /// recorded as soon as it arrives, so a retry after a failure only
  /// writes what is left.
  ///
  /// [confirmed]: the pending answers confirmed by « oui » (EPIC-16).
  Future<void> submit({Set<String> confirmed = const {}}) async {
    if (state.isSubmitting) return;
    emit(state.copyWith(submission: LifestyleSubmission.inProgress));
    final drafts = [...state.assets, ...state.watchPoints];
    final wanted = [
      for (final (i, draft) in state.assets.indexed)
        _traced(draft, confirmed).toItem(propertyId: _propertyId, sortOrder: i),
      for (final (i, draft) in state.watchPoints.indexed)
        _traced(draft, confirmed).toItem(propertyId: _propertyId, sortOrder: i),
    ];
    final resolutions = <PendingResolution, List<String>>{};
    for (final MapEntry(key: id, value: answer) in _pending.entries) {
      final draft = drafts.where((d) => d.pendingId == id).firstOrNull;
      final kept =
          draft != null && draft.label == '${answer.values['label']}'.trim();
      final resolution = draft == null
          ? PendingResolution.erased
          : !kept
          ? PendingResolution.modified
          : confirmed.contains(id)
          ? PendingResolution.yes
          : PendingResolution.continueTapped;
      (resolutions[resolution] ??= []).add(id);
    }
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
          pendingResolutions: resolutions,
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
