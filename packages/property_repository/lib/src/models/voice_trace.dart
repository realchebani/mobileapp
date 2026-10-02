import 'package:equatable/equatable.dart';
import 'package:property_repository/src/models/enums.dart';
import 'package:property_repository/src/models/json.dart';

/// EPIC-16 · where a saved value comes from (`field_sources.<column>.s`).
enum FieldSourceKind implements DbEnum {
  /// Said on its own step (voice sheet).
  dictated('dicte'),

  /// Said on another step, pre-filled « À confirmer », then confirmed.
  dictatedElsewhere('dicte_autre_etape'),

  /// Typed on screen.
  typed('saisi'),

  /// Read on a plan or a photo (EPIC-15).
  extracted('extrait'),

  /// Address base, cadastre, copied from another property.
  external('externe');

  new(this.value);

  @override
  final String value;
}

/// How a pending answer was confirmed (`field_sources.<column>.c`).
enum FieldConfirmation implements DbEnum {
  /// « Continuer » on the step showing it.
  continueTapped('continuer'),

  /// « Oui » said or tapped.
  yes('oui'),

  /// An update of a validated step accepted from the voice sheet.
  update('mise_a_jour');

  new(this.value);

  @override
  final String value;
}

/// {@template field_source}
/// The origin of one saved value (`field_sources` of `properties`, `rooms`,
/// `previous_estimates`, `lifestyle_items`): written by the app in the same
/// request as the value, read by the expert's fill sheet.
/// {@endtemplate}
class FieldSource extends Equatable {
  /// {@macro field_source}
  const new({
    required this.kind,
    required this.at,
    this.turnId,
    this.evidenceKey,
    this.pendingId,
    this.confirmation,
  });

  /// A value typed on screen at [at].
  const new typed(DateTime at) : this(kind: FieldSourceKind.typed, at: at);

  /// Reads an entry, or null when it is not one.
  static FieldSource? tryParse(Object? json) {
    if (json is! Map) return null;
    final kind = parseDbEnum(FieldSourceKind.values, json['s']);
    final raw = json['at'];
    final at = raw is String ? DateTime.tryParse(raw) : null;
    if (kind == null || at == null) return null;
    return FieldSource(
      kind: kind,
      at: at,
      turnId: json['t'] as String?,
      evidenceKey: json['k'] as String?,
      pendingId: json['p'] as String?,
      confirmation: parseDbEnum(FieldConfirmation.values, json['c']),
    );
  }

  final FieldSourceKind kind;

  /// When the app saved the value.
  final DateTime at;

  /// The agent turn the value was said in.
  final String? turnId;

  /// The key of the value in that turn's evidence (`purchase_year`,
  /// `op:0.area_m2`, `note:0`…).
  final String? evidenceKey;

  /// The accepted pending answer.
  final String? pendingId;
  final FieldConfirmation? confirmation;

  Map<String, Object?> toJson() => {
    's': kind.value,
    't': ?turnId,
    'k': ?evidenceKey,
    'p': ?pendingId,
    'c': ?confirmation?.value,
    'at': at.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [
    kind,
    at,
    turnId,
    evidenceKey,
    pendingId,
    confirmation,
  ];
}

/// [current] (a `field_sources` map) with [updates] applied, to send in the
/// same patch as the values; other entries are kept.
Map<String, Object?> mergeFieldSourceMaps(
  Map<String, Object?> current,
  Map<String, FieldSource> updates,
) => {
  ...current,
  for (final MapEntry(:key, :value) in updates.entries) key: value.toJson(),
};

/// Keys of `properties.step_notes` (« Notes complémentaires » per step).
abstract final class StepNoteKeys {
  static const location = 'location';
  static const context = 'context';
  static const technical = 'technical';
  static const rooms = 'rooms';
  static const lifestyle = 'lifestyle';

  static const List<String> all = [
    location,
    context,
    technical,
    rooms,
    lifestyle,
  ];

  /// Longest note of a step.
  static const maxLength = 1000;

  /// The `field_sources` key of the note of [step].
  static String sourceKey(String step) => 'step_notes.$step';
}

/// Status of a pending answer (`pending_answers.status`).
enum PendingStatus implements DbEnum {
  pending('pending'),
  accepted('accepted'),
  rejected('rejected'),
  superseded('superseded'),
  expired('expired');

  new(this.value);

  @override
  final String value;
}

/// How a pending answer was closed (`pending_answers.resolution`).
enum PendingResolution implements DbEnum {
  /// Accepted by « Continuer ».
  continueTapped('continuer'),

  /// Accepted by « oui ».
  yes('oui'),

  /// Refused by « non ».
  no('non'),

  /// Changed on screen.
  modified('modifie'),

  /// Erased on screen.
  erased('efface'),

  /// Undone from the voice sheet.
  cancelled('annule'),

  /// Replaced by another value said on its step.
  replaced('remplace'),

  /// Expired at submission (backend only).
  submitted('envoi');

  new(this.value);

  @override
  final String value;

  /// The status this resolution gives.
  PendingStatus get status => switch (this) {
    continueTapped || yes => PendingStatus.accepted,
    no || modified || erased || cancelled => PendingStatus.rejected,
    replaced => PendingStatus.superseded,
    submitted => PendingStatus.expired,
  };
}

/// What a pending answer holds (`pending_answers.kind`).
enum PendingKind implements DbEnum {
  field('field'),
  room('room'),
  previousEstimate('previous_estimate'),
  lifestyleItem('lifestyle_item'),
  note('note');

  new(this.value);

  @override
  final String value;
}

/// {@template pending_answer}
/// EPIC-16 · a value said on one step for another one
/// (`pending_answers`), pre-filled « À confirmer » on [targetStep] and never
/// applied without the seller's gesture.
/// {@endtemplate}
class PendingAnswer extends Equatable {
  /// {@macro pending_answer}
  const new({
    required this.id,
    required this.propertyId,
    required this.targetStep,
    required this.kind,
    required this.value,
    required this.label,
    required this.quote,
    required this.sourceStep,
    this.field,
    this.changedLabel,
    this.confidence,
    this.turnId,
    this.status = PendingStatus.pending,
    this.createdAt,
  });

  /// Builds an answer from a `pending_answers` row.
  factory fromJson(Map<String, dynamic> json) => PendingAnswer(
    id: json['id'] as String,
    propertyId: json['property_id'] as String,
    targetStep: json['target_step'] as String,
    kind: parseDbEnum(PendingKind.values, json['kind']) ?? PendingKind.note,
    field: json['field'] as String?,
    value: json['value'],
    label: json['label_fr'] as String? ?? '',
    changedLabel: json['changed_fr'] as String?,
    quote: json['quote'] as String? ?? '',
    confidence: readDouble(json['confidence']),
    sourceStep: json['source_step'] as String? ?? '',
    turnId: json['turn_id'] as String?,
    status:
        parseDbEnum(PendingStatus.values, json['status']) ??
        PendingStatus.pending,
    createdAt: readDateTime(json['created_at']),
  );

  final String id;
  final String propertyId;

  /// The agent step it is pre-filled on (`technical`…).
  final String targetStep;
  final PendingKind kind;

  /// The `properties` column ([PendingKind.field]).
  final String? field;

  /// As stored: a code, a number, a list; an entity's values; a note.
  final Object? value;

  /// "Construction 1998".
  final String label;

  /// "Construction : 1990 → 1998" when it replaces a saved value.
  final String? changedLabel;

  /// The words it comes from.
  final String quote;
  final double? confidence;

  /// The step where it was said.
  final String sourceStep;
  final String? turnId;
  final PendingStatus status;
  final DateTime? createdAt;

  /// Whether the model was unsure (a « ? » in its pill).
  bool get unsure => (confidence ?? 1) < 0.7;

  /// The values of an entity ([PendingKind.room]…), or empty.
  Map<String, Object?> get values => value is Map
      ? Map<String, Object?>.from(value! as Map)
      : const <String, Object?>{};

  @override
  List<Object?> get props => [
    id,
    propertyId,
    targetStep,
    kind,
    field,
    value,
    label,
    changedLabel,
    quote,
    confidence,
    sourceStep,
    turnId,
    status,
    createdAt,
  ];
}
