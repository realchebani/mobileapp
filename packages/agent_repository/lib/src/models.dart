import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Tunnel step the agent works on (`agent_sessions.step`). V1 has no voice
/// (EPIC-16).
enum AgentStep {
  /// V2 · situations particulières (the address is only dictated).
  location('location'),

  /// V3 · contexte & type de bien.
  context('context'),

  /// V4 · audit technique (fields of V4b).
  technical('technical'),

  /// V5c · dictée des pièces.
  rooms('rooms'),

  /// V6 · cadre de vie.
  lifestyle('lifestyle');

  new(this.value);

  final String value;

  static AgentStep? parse(Object? value) {
    for (final step in values) {
      if (step.value == value) return step;
    }
    return null;
  }
}

/// A recorded utterance, transcribed (`agent-transcribe`).
final class Transcription extends Equatable {
  const new({required this.turnId, required this.transcript});

  final String turnId;
  final String transcript;

  @override
  List<Object?> get props => [turnId, transcript];
}

/// A pill of the conversation: an understood answer ("Construction 1998")
/// or a pending question ("Assainissement ?").
final class AgentPill extends Equatable {
  const new({
    required this.field,
    required this.label,
    this.changedLabel,
    this.corrected = false,
  });

  new fromJson(Map<String, dynamic> json)
    : this(
        field: json['field'] as String,
        label: json['label_fr'] as String,
        changedLabel: json['changed_fr'] as String?,
        corrected: json['corrected'] as bool? ?? false,
      );

  /// The `properties` column ("entity" for a question about an entity).
  final String field;

  /// French label (from the server).
  final String label;

  /// "Modifié : 1998 → 1999" when the answer replaces a known value.
  final String? changedLabel;

  /// The seller corrected the value ("non, plutôt…").
  final bool corrected;

  @override
  List<Object?> get props => [field, label, changedLabel, corrected];
}

/// A lifestyle item proposed by the agent (V6).
final class AgentLifestyleItem extends Equatable {
  const new({required this.isAsset, required this.label});

  new fromJson(Map<String, dynamic> json)
    : this(isAsset: json['kind'] == 'asset', label: json['label'] as String);

  /// An asset, otherwise a watch point.
  final bool isAsset;
  final String label;

  @override
  List<Object?> get props => [isAsset, label];
}

/// Kind of an entity the agent changes.
enum AgentEntity {
  /// V5c · a room.
  room('room'),

  /// V3 · a previous agency estimate.
  previousEstimate('previous_estimate');

  new(this.value);

  final String value;

  static AgentEntity? parse(Object? value) {
    for (final entity in values) {
      if (entity.value == value) return entity;
    }
    return null;
  }
}

/// What happens to an entity.
enum AgentEntityOp {
  create('create'),
  update('update'),
  delete('delete');

  new(this.value);

  final String value;

  static AgentEntityOp parse(Object? value) => switch (value) {
    'update' => update,
    'delete' => delete,
    _ => create,
  };
}

/// A validated change of an entity: a room created, a previous estimate
/// updated… [target] is `new` or the short reference
/// the app sent (R1, E2…); [values] are as stored (`area_m2`, `level`…;
/// a room also has its `kind`, the `RoomSuggestion` name).
final class AgentEntityChange extends Equatable {
  const new({
    required this.entity,
    required this.op,
    required this.target,
    required this.label,
    this.values = const {},
    this.changedLabel,
    this.corrected = false,
  });

  new fromJson(Map<String, dynamic> json)
    : this(
        entity: AgentEntity.parse(json['entity']) ?? AgentEntity.room,
        op: AgentEntityOp.parse(json['op']),
        target: json['target'] as String? ?? 'new',
        label: json['label_fr'] as String? ?? '',
        values: Map<String, Object?>.from(
          json['values'] as Map? ?? const <String, Object?>{},
        ),
        changedLabel: json['changed_fr'] as String?,
        corrected: json['corrected'] as bool? ?? false,
      );

  final AgentEntity entity;
  final AgentEntityOp op;
  final String target;

  /// "Séjour · RDC · 38 m² · Parquet chêne".
  final String label;
  final Map<String, Object?> values;

  /// "Modifiée : 38 → 40 m²".
  final String? changedLabel;
  final bool corrected;

  /// Whether this creates a new entity.
  bool get isNew => target == 'new';

  /// This change aimed at [target] (a stable id instead of a short
  /// reference).
  AgentEntityChange withTarget(String target) => AgentEntityChange(
    entity: entity,
    op: op,
    target: target,
    label: label,
    values: values,
    changedLabel: changedLabel,
    corrected: corrected,
  );

  @override
  List<Object?> get props => [
    entity,
    op,
    target,
    label,
    values,
    changedLabel,
    corrected,
  ];
}

/// Why a change waits for the seller's "Oui".
enum AgentConfirmationReason {
  typeChange('type_change'),
  delete('delete'),
  mediumConfidence('medium_confidence'),
  strongChange('strong_change'),
  clearSituations('clear_situations'),
  mergeRoom('merge_room');

  new(this.value);

  final String value;

  static AgentConfirmationReason parse(Object? value) {
    for (final reason in values) {
      if (reason.value == value) return reason;
    }
    return mediumConfidence;
  }
}

/// A change applied only once the seller says or taps "Oui" ("Type :
/// garage ?", "Supprimer Cellier (4,2 m²) ?").
final class AgentConfirmation extends Equatable {
  const new({
    required this.id,
    required this.reason,
    required this.label,
    this.patch = const {},
    this.entityOps = const [],
  });

  new fromJson(Map<String, dynamic> json)
    : this(
        id: json['id'] as String,
        reason: AgentConfirmationReason.parse(json['reason']),
        label: json['label_fr'] as String,
        patch: Map<String, Object?>.from(
          json['patch'] as Map? ?? const <String, Object?>{},
        ),
        entityOps: [
          for (final op in json['entity_ops'] as List? ?? const [])
            AgentEntityChange.fromJson(Map<String, dynamic>.from(op as Map)),
        ],
      );

  final String id;
  final AgentConfirmationReason reason;
  final String label;
  final Map<String, Object?> patch;
  final List<AgentEntityChange> entityOps;

  @override
  List<Object?> get props => [id, reason, label, patch, entityOps];
}

/// An answer about another step: never written ("Construction →
/// Technique").
final class AgentOutOfStep extends Equatable {
  const new({required this.field, required this.step, required this.label});

  new fromJson(Map<String, dynamic> json)
    : this(
        field: json['field'] as String,
        step: json['step'] as String,
        label: json['label_fr'] as String,
      );

  final String field;

  /// The agent step where it is asked (`technical`…).
  final String step;
  final String label;

  @override
  List<Object?> get props => [field, step, label];
}

/// What a value said for another step is (`pending_answers.kind`).
enum AgentCrossStepKind {
  field('field'),
  room('room'),
  previousEstimate('previous_estimate'),
  lifestyleItem('lifestyle_item'),
  note('note');

  new(this.value);

  final String value;

  static AgentCrossStepKind parse(Object? value) {
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    return note;
  }
}

/// A value said on one step for another one (EPIC-16), kept by the server
/// as a pending answer ([id]) and pre-filled « À confirmer » on
/// [targetStep]: "Noté pour Technique · Construction 1998".
final class AgentCrossStep extends Equatable {
  const new({
    required this.id,
    required this.targetStep,
    required this.kind,
    required this.label,
    this.field,
    this.value,
    this.changedLabel,
    this.quote = '',
    this.confidence = 1,
  });

  new fromJson(Map<String, dynamic> json)
    : this(
        id: json['id'] as String,
        targetStep: AgentStep.parse(json['target_step']) ?? AgentStep.technical,
        kind: AgentCrossStepKind.parse(json['kind']),
        field: json['field'] as String?,
        value: json['value'],
        label: json['label_fr'] as String? ?? '',
        changedLabel: json['changed_fr'] as String?,
        quote: json['quote'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
      );

  /// The `pending_answers` row.
  final String id;
  final AgentStep targetStep;
  final AgentCrossStepKind kind;

  /// The `properties` column ([AgentCrossStepKind.field]).
  final String? field;

  /// As stored: a code, a number, a list; the values of an entity; a note.
  final Object? value;

  /// "Construction 1998".
  final String label;

  /// "Construction : 1998 → 1999" when it replaces a saved value.
  final String? changedLabel;

  /// The words it comes from.
  final String quote;
  final double confidence;

  /// Whether the model was unsure (0,5–0,7): a « ? » in the pill.
  bool get unsure => confidence < 0.7;

  @override
  List<Object?> get props => [
    id,
    targetStep,
    kind,
    field,
    value,
    label,
    changedLabel,
    quote,
    confidence,
  ];
}

/// The answer of one agent turn (`agent-turn`). The server validated
/// [patch] (column → value as stored: codes, numbers, lists) and
/// [entityOps]; the app writes them itself.
final class AgentTurn extends Equatable {
  const new({
    required this.turnId,
    required this.transcript,
    required this.reply,
    this.patch = const {},
    this.facts = const [],
    this.pending = const [],
    this.lifestyleItems = const [],
    this.suggestions = const {},
    this.entityOps = const [],
    this.confirmations = const [],
    this.outOfStep = const [],
    this.corrections = const [],
    this.notes = const [],
    this.crossStep = const [],
    this.supersededIds = const [],
    this.nextField,
    this.done = false,
  });

  new fromJson(Map<String, dynamic> json)
    : this(
        turnId: json['turn_id'] as String,
        transcript: json['transcript'] as String? ?? '',
        reply: json['reply_fr'] as String? ?? '',
        patch: Map<String, Object?>.from(
          json['patch'] as Map? ?? const <String, Object?>{},
        ),
        facts: _pills(json['facts']),
        pending: _pills(json['pending']),
        lifestyleItems: [
          for (final item in json['lifestyle_items'] as List? ?? const [])
            AgentLifestyleItem.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        suggestions: Map<String, String>.from(
          json['suggestions'] as Map? ?? const <String, String>{},
        ),
        entityOps: [
          for (final op in json['entity_ops'] as List? ?? const [])
            AgentEntityChange.fromJson(Map<String, dynamic>.from(op as Map)),
        ],
        confirmations: [
          for (final item in json['confirmations'] as List? ?? const [])
            AgentConfirmation.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        outOfStep: [
          for (final item in json['out_of_step'] as List? ?? const [])
            AgentOutOfStep.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        corrections: [
          for (final item in json['corrections'] as List? ?? const [])
            item as String,
        ],
        notes: [
          for (final note in json['notes'] as List? ?? const [])
            (note as Map)['text'] as String,
        ],
        crossStep: [
          for (final item in json['cross_step'] as List? ?? const [])
            AgentCrossStep.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        supersededIds: [
          for (final id in json['superseded_ids'] as List? ?? const [])
            id as String,
        ],
        nextField: json['next_field'] as String?,
        done: json['done'] as bool? ?? false,
      );

  /// The change confirmed by the seller ([confirmation] of [turnId]), as a
  /// turn of its own (applied and undone like the others).
  factory confirmed(String turnId, AgentConfirmation confirmation) => AgentTurn(
    turnId: '$turnId#${confirmation.id}',
    transcript: '',
    reply: '',
    patch: confirmation.patch,
    facts: [
      if (confirmation.patch.isNotEmpty || confirmation.entityOps.isEmpty)
        AgentPill(
          field: confirmation.patch.keys.firstOrNull ?? 'confirmation',
          label: _withoutQuestion(confirmation.label),
        ),
    ],
    entityOps: confirmation.entityOps,
  );

  static List<AgentPill> _pills(Object? json) => [
    for (final pill in json as List? ?? const [])
      AgentPill.fromJson(Map<String, dynamic>.from(pill as Map)),
  ];

  /// "Type : garage ?" → "Type : garage".
  static String _withoutQuestion(String label) =>
      label.replaceFirst(RegExp(r'[\s ]*\?$'), '');

  final String turnId;
  final String transcript;

  /// The agent's reply, in French.
  final String reply;
  final Map<String, Object?> patch;
  final List<AgentPill> facts;
  final List<AgentPill> pending;
  final List<AgentLifestyleItem> lifestyleItems;

  /// Proposed, never imposed (e.g. `secret_note`).
  final Map<String, String> suggestions;

  /// Rooms, previous estimates (co-owners only through a confirmation).
  final List<AgentEntityChange> entityOps;

  /// Changes waiting for the seller's "Oui".
  final List<AgentConfirmation> confirmations;

  /// Answers about other steps (never written).
  final List<AgentOutOfStep> outOfStep;

  /// Columns (or "room:R3"…) the seller corrected.
  final List<String> corrections;

  /// What was said on the step and fits no field: appended to its « Notes
  /// complémentaires ».
  final List<String> notes;

  /// Values said for other steps, kept as pending answers.
  final List<AgentCrossStep> crossStep;

  /// Pending answers replaced by this turn's [crossStep].
  final List<String> supersededIds;
  final String? nextField;

  /// Whether nothing useful is missing any more.
  final bool done;

  /// Whether something was understood (applied, proposed or to confirm).
  bool get understood =>
      patch.isNotEmpty ||
      lifestyleItems.isNotEmpty ||
      suggestions.isNotEmpty ||
      entityOps.isNotEmpty ||
      confirmations.isNotEmpty ||
      notes.isNotEmpty ||
      crossStep.isNotEmpty;

  AgentTurn _copy({
    required List<AgentEntityChange> entityOps,
    Map<String, Object?>? patch,
    List<AgentPill>? facts,
    List<String>? notes,
    List<AgentCrossStep>? crossStep,
  }) => AgentTurn(
    turnId: turnId,
    transcript: transcript,
    reply: reply,
    patch: patch ?? this.patch,
    facts: facts ?? this.facts,
    pending: pending,
    lifestyleItems: lifestyleItems,
    suggestions: suggestions,
    entityOps: entityOps,
    confirmations: confirmations,
    outOfStep: outOfStep,
    corrections: corrections,
    notes: notes ?? this.notes,
    crossStep: crossStep ?? this.crossStep,
    supersededIds: supersededIds,
    nextField: nextField,
    done: done,
  );

  /// This turn with [ops] as its entity operations (e.g. short
  /// references resolved to stable ids by the form).
  AgentTurn withEntityOps(List<AgentEntityChange> ops) => _copy(entityOps: ops);

  /// This turn without the answer [key] (the seller undid that pill): a
  /// column of [patch] (its fact too), `op:<index>` of [entityOps],
  /// `note:<index>` of [notes] or `x:<pending id>` of [crossStep].
  AgentTurn without(String key) {
    int? indexOf(String prefix) => key.startsWith(prefix)
        ? int.tryParse(key.substring(prefix.length))
        : null;
    final op = indexOf('op:');
    final note = indexOf('note:');
    final cross = key.startsWith('x:') ? key.substring(2) : null;
    return _copy(
      patch: {
        for (final MapEntry(key: column, :value) in patch.entries)
          if (column != key) column: value,
      },
      facts: [
        for (final fact in facts)
          if (fact.field != key) fact,
      ],
      entityOps: [
        for (final (i, change) in entityOps.indexed)
          if (i != op) change,
      ],
      notes: [
        for (final (i, text) in notes.indexed)
          if (i != note) text,
      ],
      crossStep: [
        for (final item in crossStep)
          if (item.id != cross) item,
      ],
    );
  }

  @override
  List<Object?> get props => [
    turnId,
    transcript,
    reply,
    patch,
    facts,
    pending,
    lifestyleItems,
    suggestions,
    entityOps,
    confirmations,
    outOfStep,
    corrections,
    notes,
    crossStep,
    supersededIds,
    nextField,
    done,
  ];
}

/// A row of the V5c table sent to the agent (short reference R1…; never
/// the room's id nor its description).
final class AgentRoom extends Equatable {
  const new({
    required this.ref,
    required this.name,
    required this.areaM2,
    this.level,
    this.floorCovering,
    this.glazing,
    this.ceilingHeightM,
    this.isAnnex = false,
  });

  final String ref;
  final String name;
  final double areaM2;

  /// Stored codes (`rdc`, `parquet_chene`, `double`…).
  final String? level;
  final String? floorCovering;
  final String? glazing;
  final double? ceilingHeightM;
  final bool isAnnex;

  Map<String, Object?> toJson() => {
    'ref': ref,
    'name': name,
    'area_m2': areaM2,
    'level': level,
    'floor_covering': floorCovering,
    'glazing': glazing,
    'ceiling_height_m': ceilingHeightM,
    'is_annex': isAnnex,
  };

  @override
  List<Object?> get props => [
    ref,
    name,
    areaM2,
    level,
    floorCovering,
    glazing,
    ceilingHeightM,
    isAnnex,
  ];
}

/// A V3 estimate card sent to the agent (short reference E1…).
final class AgentEstimate extends Equatable {
  const new({required this.ref, this.priceEur, this.month, this.agencyName});

  final String ref;
  final int? priceEur;

  /// The month (day ignored).
  final DateTime? month;
  final String? agencyName;

  Map<String, Object?> toJson() => {
    'ref': ref,
    'price_eur': priceEur,
    'estimated_month': month == null
        ? null
        : '${month!.year.toString().padLeft(4, '0')}-'
              '${month!.month.toString().padLeft(2, '0')}-01',
    'agency_name': agencyName,
  };

  @override
  List<Object?> get props => [ref, priceEur, month, agencyName];
}

/// What the screen sends with a turn of a step sheet (EPIC-14): its
/// unsaved answers and entities. [interactive] lets the server ask
/// confirmations (the V4 "Night" audit does not).
final class AgentTurnContext extends Equatable {
  const new({
    this.interactive = true,
    this.draft = const {},
    this.rooms = const [],
    this.estimates = const [],
    this.lastRoomRef,
  });

  final bool interactive;

  /// Unsaved values of the step's columns (as stored).
  final Map<String, Object?> draft;
  final List<AgentRoom> rooms;
  final List<AgentEstimate> estimates;

  /// The room dictated last ("la dernière").
  final String? lastRoomRef;

  Map<String, Object?> toJson() => {
    'interactive': interactive,
    if (draft.isNotEmpty) 'draft': draft,
    if (rooms.isNotEmpty) 'rooms': [for (final room in rooms) room.toJson()],
    if (estimates.isNotEmpty)
      'estimates': [for (final estimate in estimates) estimate.toJson()],
    'last_room_ref': ?lastRoomRef,
  };

  @override
  List<Object?> get props => [
    interactive,
    draft,
    rooms,
    estimates,
    lastRoomRef,
  ];
}

/// Spoken reply (`agent-speech`).
final class AgentSpeech extends Equatable {
  const new({required this.bytes, required this.format});

  final Uint8List bytes;

  /// `mp3` or `wav`.
  final String format;

  @override
  List<Object?> get props => [bytes, format];
}
