part of 'step_trace_cubit.dart';

/// What a step saves besides its answers (EPIC-16): its « Notes
/// complémentaires », the origin of each value (`field_sources`) and the
/// resolution of the pending answers it showed « À confirmer ».
final class StepTraceSave extends Equatable {
  const new({required this.patch, this.resolutions = const {}});

  /// The step's patch with `field_sources` and `step_notes`.
  final Map<String, Object?> patch;

  /// Pending answers to close once the patch is saved.
  final Map<PendingResolution, List<String>> resolutions;

  @override
  List<Object?> get props => [patch, resolutions];
}

/// The pending answers of a step pre-filled « À confirmer », its notes, and
/// what the seller confirmed by voice.
final class StepTraceState extends Equatable {
  const new({
    this.noteKey,
    this.notes = '',
    this.savedNotes = '',
    this.prefilled = const [],
    this.confirmed = const {},
    this.dictatedNotes,
    this.notesTurnId,
  });

  /// The step from its dossier: its saved note, the pending answers of the
  /// step (their values pre-fill the form; a pending note is appended to
  /// the notes).
  factory fromProperty(
    Property property, {
    required String? noteKey,
    List<PendingAnswer> pending = const [],
  }) {
    final saved = noteKey == null ? '' : property.stepNoteOf(noteKey) ?? '';
    final notes = [
      if (saved.isNotEmpty) saved,
      for (final answer in pending)
        if (answer.kind == PendingKind.note && answer.value is String)
          answer.value! as String,
    ].join(separator);
    return StepTraceState(
      noteKey: noteKey,
      notes: noteKey == null ? '' : _cut(notes),
      savedNotes: saved,
      prefilled: pending,
    );
  }

  /// Between two notes appended.
  static const separator = ' · ';

  static String _cut(String text) => text.length > StepNoteKeys.maxLength
      ? text.substring(0, StepNoteKeys.maxLength)
      : text;

  /// The `step_notes` key of the step, or null (no notes on this step).
  final String? noteKey;

  /// The notes as shown (typed, dictated or pre-filled).
  final String notes;
  final String savedNotes;

  /// Pending answers of this step, pre-filled « À confirmer ».
  final List<PendingAnswer> prefilled;

  /// Pending answers confirmed by « oui » (the others by « Continuer »).
  final Set<String> confirmed;

  /// [notes] right after the last dictated note, and its turn.
  final String? dictatedNotes;
  final String? notesTurnId;

  /// The pre-filled answer of [column], if any.
  PendingAnswer? prefilledField(String column) => prefilled
      .where((a) => a.kind == PendingKind.field && a.field == column)
      .firstOrNull;

  /// Pre-filled answers of [kind] (rooms, estimates, items, notes).
  List<PendingAnswer> prefilledOf(PendingKind kind) => [
    for (final answer in prefilled)
      if (answer.kind == kind) answer,
  ];

  /// Whether [column] shows « À confirmer »: pre-filled, not confirmed yet
  /// and still holding the value said ([value] as stored).
  bool toConfirm(String column, Object? value) {
    final answer = prefilledField(column);
    return answer != null &&
        !confirmed.contains(answer.id) &&
        sameStoredValue(answer.value, value);
  }

  /// Whether [column] was pre-filled and confirmed by « oui ».
  bool isConfirmed(String column) {
    final answer = prefilledField(column);
    return answer != null && confirmed.contains(answer.id);
  }

  /// Whether the notes hold a pre-filled note not confirmed yet.
  bool get notesToConfirm => prefilledOf(PendingKind.note)
      .any((a) => !confirmed.contains(a.id) && notes.contains('${a.value}'));

  /// The labels of what is pre-filled and not confirmed (the sheet's
  /// intro: « J’ai déjà noté : … »).
  List<String> get toConfirmLabels => [
    for (final answer in prefilled)
      if (!confirmed.contains(answer.id)) answer.label,
  ];

  /// [property] with the pre-filled values of the fields (the form starts
  /// from it; the dossier itself is unchanged).
  Property prefilledProperty(Property property) {
    final fields = prefilledOf(PendingKind.field);
    if (fields.isEmpty) return property;
    return Property.fromJson({
      ...property.toJson(),
      for (final answer in fields) answer.field!: answer.value,
    });
  }

  /// [patch] (the step's columns, as stored) with the origin of each
  /// changed value, the notes, and the resolution of the pre-filled
  /// answers ([voiceSource]: the turn that said a value, see
  /// `VoiceFormMixin.voiceSourceOf`; [kinds]: the source of the columns that
  /// were not typed, e.g. the address base or a plan).
  StepTraceSave saveFor({
    required Property property,
    required Map<String, Object?> patch,
    required FieldSource? Function(String column, Object? value) voiceSource,
    required DateTime now,
    Map<String, FieldSourceKind> kinds = const {},
  }) {
    final saved = property.toJson();
    final sources = <String, FieldSource>{};
    final resolutions = <PendingResolution, List<String>>{};
    void resolve(PendingResolution resolution, String id) =>
        (resolutions[resolution] ??= []).add(id);
    for (final MapEntry(key: column, value: raw) in patch.entries) {
      if (_untraced.contains(column)) continue;
      final value = _stored(raw);
      final answer = prefilledField(column);
      final unchanged = sameStoredValue(saved[column], value);
      if (answer != null && sameStoredValue(answer.value, value)) {
        final yes = confirmed.contains(answer.id);
        resolve(
          yes ? PendingResolution.yes : PendingResolution.continueTapped,
          answer.id,
        );
        if (!unchanged) {
          sources[column] = FieldSource(
            kind: FieldSourceKind.dictatedElsewhere,
            at: now,
            turnId: answer.turnId,
            pendingId: answer.id,
            confirmation: yes
                ? FieldConfirmation.yes
                : FieldConfirmation.continueTapped,
          );
        }
        continue;
      }
      final voice = voiceSource(column, value);
      if (answer != null) {
        resolve(
          voice != null
              ? PendingResolution.replaced
              : _isEmpty(value)
              ? PendingResolution.erased
              : PendingResolution.modified,
          answer.id,
        );
      }
      if (unchanged) continue;
      final kind = kinds[column];
      sources[column] =
          voice ??
          (kind == null
              ? FieldSource.typed(now)
              : FieldSource(kind: kind, at: now));
    }
    final full = {...patch};
    final key = noteKey;
    if (key != null) {
      final text = notes.trim();
      var accepted = false;
      for (final answer in prefilledOf(PendingKind.note)) {
        final kept = text.contains('${answer.value}');
        accepted |= kept;
        resolve(
          kept
              ? confirmed.contains(answer.id)
                    ? PendingResolution.yes
                    : PendingResolution.continueTapped
              : text.isEmpty
              ? PendingResolution.erased
              : PendingResolution.modified,
          answer.id,
        );
      }
      if (text != savedNotes.trim()) {
        full[PropertyColumns.stepNotes] = property.withStepNote(key, text);
        final turn = notesTurnId;
        sources[StepNoteKeys.sourceKey(
          key,
        )] = turn != null && dictatedNotes?.trim() == text
            ? FieldSource(
                kind: FieldSourceKind.dictated,
                at: now,
                turnId: turn,
                evidenceKey: 'note:0',
              )
            : accepted
            ? FieldSource(kind: FieldSourceKind.dictatedElsewhere, at: now)
            : FieldSource.typed(now);
      }
    }
    if (sources.isNotEmpty) {
      full[PropertyColumns.fieldSources] = property.mergeFieldSources(sources);
    }
    return StepTraceSave(patch: full, resolutions: resolutions);
  }

  /// Columns that are not answers.
  static const Set<String> _untraced = {
    PropertyColumns.currentStep,
    PropertyColumns.provenance,
    PropertyColumns.fieldSources,
    PropertyColumns.stepNotes,
    PropertyColumns.status,
    PropertyColumns.submittedAt,
    PropertyColumns.transparencyScore,
  };

  static Object? _stored(Object? value) => encodeVoiceDraft({'v': value})['v'];

  static bool _isEmpty(Object? value) =>
      value == null || (value is List && value.isEmpty);

  StepTraceState copyWith({
    String? notes,
    Set<String>? confirmed,
    String? Function()? dictatedNotes,
    String? Function()? notesTurnId,
  }) {
    return StepTraceState(
      noteKey: noteKey,
      notes: notes ?? this.notes,
      savedNotes: savedNotes,
      prefilled: prefilled,
      confirmed: confirmed ?? this.confirmed,
      dictatedNotes: dictatedNotes == null
          ? this.dictatedNotes
          : dictatedNotes(),
      notesTurnId: notesTurnId == null ? this.notesTurnId : notesTurnId(),
    );
  }

  @override
  List<Object?> get props => [
    noteKey,
    notes,
    savedNotes,
    prefilled,
    confirmed,
    dictatedNotes,
    notesTurnId,
  ];
}
