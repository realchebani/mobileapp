part of 'lifestyle_cubit.dart';

/// Progress of [LifestyleCubit.submit].
enum LifestyleSubmission { idle, inProgress, success, failure }

/// V6 form: assets, watch points, noise, overlooking and secret note. Every
/// answer is optional.
final class LifestyleState extends Equatable {
  const new({
    this.assets = const [],
    this.watchPoints = const [],
    this.noiseLevel,
    this.overlooking,
    this.secretNote = '',
    this.submission = LifestyleSubmission.idle,
    this.savedItems = const [],
    this.secretNoteSuggestion,
    this.dictated = const {},
  });

  final List<LifestyleItemDraft> assets;
  final List<LifestyleItemDraft> watchPoints;

  /// 1 (very quiet) to 10 (very noisy); null until the slider is touched.
  final int? noiseLevel;

  final Overlooking? overlooking;

  /// As typed (trimmed when saved).
  final String secretNote;

  final LifestyleSubmission submission;

  /// The `lifestyle_items` rows after a successful [LifestyleCubit.submit],
  /// assets then watch points, each by sort order.
  final List<LifestyleItem> savedItems;

  /// A secret note proposed by the voice agent: shown as a suggestion,
  /// never written unless the seller uses it.
  final String? secretNoteSuggestion;

  /// Columns answered by voice on this visit ("Dicté").
  final Set<String> dictated;

  bool get isSubmitting => submission == LifestyleSubmission.inProgress;

  /// The list of [kind].
  List<LifestyleItemDraft> itemsOf(LifestyleItemKind kind) => switch (kind) {
    LifestyleItemKind.asset => assets,
    LifestyleItemKind.watchPoint => watchPoints,
  };

  /// Whether another item of [kind] can be added.
  bool canAdd(LifestyleItemKind kind) =>
      itemsOf(kind).length < lifestyleItemsMax;

  /// The `properties` columns of this step for [property], with their
  /// provenance: "Déclaré" when answered, none when left empty.
  Map<String, Object?> patchFor(Property property) {
    final note = secretNote.trim();
    final answers = <String, Object?>{
      PropertyColumns.noiseLevel: noiseLevel,
      PropertyColumns.overlooking: overlooking,
      PropertyColumns.secretNote: note.isEmpty ? null : note,
    };
    final provenance = property.mergeProvenance({
      for (final MapEntry(:key, :value) in answers.entries)
        if (value != null) key: Provenance.declared,
    });
    return {
      ...answers,
      PropertyColumns.provenance: {
        for (final MapEntry(:key, :value) in provenance.entries)
          if (!answers.containsKey(key) || answers[key] != null) key: value,
      },
    };
  }

  LifestyleState copyWith({
    List<LifestyleItemDraft>? assets,
    List<LifestyleItemDraft>? watchPoints,
    int? noiseLevel,
    Overlooking? overlooking,
    String? secretNote,
    LifestyleSubmission? submission,
    List<LifestyleItem>? savedItems,
    String? Function()? secretNoteSuggestion,
    Set<String>? dictated,
  }) {
    return LifestyleState(
      assets: assets ?? this.assets,
      watchPoints: watchPoints ?? this.watchPoints,
      noiseLevel: noiseLevel ?? this.noiseLevel,
      overlooking: overlooking ?? this.overlooking,
      secretNote: secretNote ?? this.secretNote,
      submission: submission ?? this.submission,
      savedItems: savedItems ?? this.savedItems,
      secretNoteSuggestion: secretNoteSuggestion == null
          ? this.secretNoteSuggestion
          : secretNoteSuggestion(),
      dictated: dictated ?? this.dictated,
    );
  }

  @override
  List<Object?> get props => [
    assets,
    watchPoints,
    noiseLevel,
    overlooking,
    secretNote,
    submission,
    savedItems,
    secretNoteSuggestion,
    dictated,
  ];
}
