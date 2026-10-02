import 'package:equatable/equatable.dart';

/// Column names of the `valuations` table.
abstract final class ValuationColumns {
  static const id = 'id';
  static const propertyId = 'property_id';
  static const valueEur = 'value_eur';
  static const lowEur = 'low_eur';
  static const highEur = 'high_eur';
  static const priceM2Eur = 'price_m2_eur';
  static const aiTrendEur = 'ai_trend_eur';
  static const estimatedDelayWeeks = 'estimated_delay_weeks';
  static const methodSteps = 'method_steps';
  static const reasons = 'reasons';
  static const delayCurve = 'delay_curve';
  static const expertQuote = 'expert_quote';
  static const description = 'description';
  static const technicalSheet = 'technical_sheet';
  static const comparables = 'comparables';
  static const comparablesNote = 'comparables_note';
  static const competitorsSummary = 'competitors_summary';
  static const competitors = 'competitors';
  static const risksNote = 'risks_note';
  static const adjustments = 'adjustments';
  static const methodSummary = 'method_summary';
  static const worksLabel = 'works_label';
  static const worksEstimateEur = 'works_estimate_eur';
  static const sources = 'sources';
  static const expertDisplayName = 'expert_display_name';
  static const expertInitials = 'expert_initials';
  static const certifiedAt = 'certified_at';
  static const validUntil = 'valid_until';
  static const reportStoragePath = 'report_storage_path';
  static const reportPages = 'report_pages';
}

/// The certified valuation of a property: the expert's structured report
/// (V9 hero, V9b tabs), written by staff (`staff_certify_property`).
///
/// The JSON sections are parsed leniently: a malformed entry is skipped
/// rather than failing the whole report.
class Valuation extends Equatable {
  const new({
    required this.id,
    required this.propertyId,
    required this.valueEur,
    required this.lowEur,
    required this.highEur,
    required this.expertDisplayName,
    required this.certifiedAt,
    required this.validUntil,
    this.priceM2Eur,
    this.aiTrendEur,
    this.estimatedDelayWeeks,
    this.methodSteps = const [],
    this.reasons = const [],
    this.delayCurve = const [],
    this.expertQuote,
    this.description,
    this.technicalSheet = const [],
    this.comparables = const [],
    this.comparablesNote,
    this.competitorsSummary,
    this.competitors = const [],
    this.risksNote,
    this.adjustments = const [],
    this.methodSummary = const [],
    this.worksLabel,
    this.worksEstimateEur,
    this.sources,
    this.expertInitials,
    this.reportStoragePath,
    this.reportPages,
  });

  factory fromJson(Map<String, dynamic> json) => Valuation(
    id: json[ValuationColumns.id] as String,
    propertyId: json[ValuationColumns.propertyId] as String,
    valueEur: (json[ValuationColumns.valueEur] as num).toInt(),
    lowEur: (json[ValuationColumns.lowEur] as num).toInt(),
    highEur: (json[ValuationColumns.highEur] as num).toInt(),
    priceM2Eur: _int(json[ValuationColumns.priceM2Eur]),
    aiTrendEur: _int(json[ValuationColumns.aiTrendEur]),
    estimatedDelayWeeks: _int(json[ValuationColumns.estimatedDelayWeeks]),
    methodSteps: _list(
      json[ValuationColumns.methodSteps],
      ValuationMethodStep.fromJson,
    ),
    reasons: _list(json[ValuationColumns.reasons], ValuationReason.fromJson),
    delayCurve: _list(
      json[ValuationColumns.delayCurve],
      ValuationDelayPoint.fromJson,
    ),
    expertQuote: _text(json[ValuationColumns.expertQuote]),
    description: _text(json[ValuationColumns.description]),
    technicalSheet: _list(
      json[ValuationColumns.technicalSheet],
      ValuationTechnicalItem.fromJson,
    ),
    comparables: _list(
      json[ValuationColumns.comparables],
      ValuationComparable.fromJson,
    ),
    comparablesNote: _text(json[ValuationColumns.comparablesNote]),
    competitorsSummary: _text(json[ValuationColumns.competitorsSummary]),
    competitors: _list(
      json[ValuationColumns.competitors],
      ValuationCompetitor.fromJson,
    ),
    risksNote: _text(json[ValuationColumns.risksNote]),
    adjustments: _list(
      json[ValuationColumns.adjustments],
      ValuationAmountLine.fromJson,
    ),
    methodSummary: _list(
      json[ValuationColumns.methodSummary],
      ValuationAmountLine.fromJson,
    ),
    worksLabel: _text(json[ValuationColumns.worksLabel]),
    worksEstimateEur: _int(json[ValuationColumns.worksEstimateEur]),
    sources: _text(json[ValuationColumns.sources]),
    expertDisplayName: json[ValuationColumns.expertDisplayName] as String,
    expertInitials: _text(json[ValuationColumns.expertInitials]),
    certifiedAt: DateTime.parse(json[ValuationColumns.certifiedAt] as String),
    validUntil: DateTime.parse(json[ValuationColumns.validUntil] as String),
    reportStoragePath: _text(json[ValuationColumns.reportStoragePath]),
    reportPages: _int(json[ValuationColumns.reportPages]),
  );

  final String id;
  final String propertyId;

  /// Certified value ("Valeur certifiée").
  final int valueEur;
  final int lowEur;
  final int highEur;
  final int? priceM2Eur;

  /// The AI trend the expert started from ("Tendance IA initiale").
  final int? aiTrendEur;
  final int? estimatedDelayWeeks;

  /// "Comment nous arrivons à ce chiffre".
  final List<ValuationMethodStep> methodSteps;

  /// "Pourquoi cette valeur".
  final List<ValuationReason> reasons;

  /// "Le prix décide du délai".
  final List<ValuationDelayPoint> delayCurve;
  final String? expertQuote;
  final String? description;

  /// "Fiche technique", each line with its provenance.
  final List<ValuationTechnicalItem> technicalSheet;

  /// DVF sales retained or excluded by the expert ("Ce qui s’est
  /// réellement vendu").
  final List<ValuationComparable> comparables;
  final String? comparablesNote;
  final String? competitorsSummary;

  /// Listings competing with the property, typed by the expert.
  final List<ValuationCompetitor> competitors;
  final String? risksNote;

  /// "Ce qui déplace le prix".
  final List<ValuationAmountLine> adjustments;

  /// "La méthode".
  final List<ValuationAmountLine> methodSummary;

  /// Works the buyer will budget, if any.
  final String? worksLabel;
  final int? worksEstimateEur;
  final String? sources;
  final String expertDisplayName;
  final String? expertInitials;
  final DateTime certifiedAt;

  /// End of validity (3 months after certification by default).
  final DateTime validUntil;

  /// Path of the optional PDF in the `valuation-reports` bucket.
  final String? reportStoragePath;
  final int? reportPages;

  /// Whether a PDF report can be downloaded.
  bool get hasReport => reportStoragePath != null;

  @override
  List<Object?> get props => [
    id,
    propertyId,
    valueEur,
    lowEur,
    highEur,
    priceM2Eur,
    aiTrendEur,
    estimatedDelayWeeks,
    methodSteps,
    reasons,
    delayCurve,
    expertQuote,
    description,
    technicalSheet,
    comparables,
    comparablesNote,
    competitorsSummary,
    competitors,
    risksNote,
    adjustments,
    methodSummary,
    worksLabel,
    worksEstimateEur,
    sources,
    expertDisplayName,
    expertInitials,
    certifiedAt,
    validUntil,
    reportStoragePath,
    reportPages,
  ];
}

/// A step of "Comment nous arrivons à ce chiffre".
class ValuationMethodStep extends Equatable {
  const new({
    required this.label,
    required this.amountEur,
    this.detail,
    this.isDelta = false,
  });

  factory fromJson(Map<String, dynamic> json) => ValuationMethodStep(
    label: json['label'] as String,
    detail: _text(json['detail']),
    amountEur: (json['amount_eur'] as num).toInt(),
    isDelta: json['is_delta'] == true,
  );

  final String label;
  final String? detail;
  final int amountEur;

  /// Whether [amountEur] is a change (shown signed) rather than a value.
  final bool isDelta;

  @override
  List<Object?> get props => [label, detail, amountEur, isDelta];
}

/// A line of "Pourquoi cette valeur".
class ValuationReason extends Equatable {
  const new({required this.text, required this.positive});

  factory fromJson(Map<String, dynamic> json) => ValuationReason(
    text: json['text'] as String,
    positive: json['positive'] != false,
  );

  final String text;

  /// `+` (true) or `−` (false).
  final bool positive;

  @override
  List<Object?> get props => [text, positive];
}

/// A point of "Le prix décide du délai".
class ValuationDelayPoint extends Equatable {
  const new({required this.priceEur, required this.label});

  factory fromJson(Map<String, dynamic> json) => ValuationDelayPoint(
    priceEur: (json['price_eur'] as num).toInt(),
    label: json['label'] as String,
  );

  final int priceEur;

  /// e.g. "≈ 5 semaines".
  final String label;

  @override
  List<Object?> get props => [priceEur, label];
}

/// Where a technical sheet value comes from.
enum ValuationProvenance {
  declared,
  document,
  external,
  verified;

  static ValuationProvenance parse(Object? value) => values.firstWhere(
    (provenance) => provenance.name == value,
    orElse: () => declared,
  );
}

/// A line of the "Fiche technique".
class ValuationTechnicalItem extends Equatable {
  const new({
    required this.label,
    required this.value,
    this.provenance = ValuationProvenance.declared,
  });

  factory fromJson(Map<String, dynamic> json) => ValuationTechnicalItem(
    label: json['label'] as String,
    value: json['value'] as String,
    provenance: ValuationProvenance.parse(json['provenance']),
  );

  final String label;
  final String value;
  final ValuationProvenance provenance;

  @override
  List<Object?> get props => [label, value, provenance];
}

/// A comparable DVF sale (street without house number).
class ValuationComparable extends Equatable {
  const new({
    required this.street,
    required this.priceEur,
    this.soldOn,
    this.areaM2,
    this.landM2,
    this.excluded = false,
  });

  factory fromJson(Map<String, dynamic> json) => ValuationComparable(
    street: json['street'] as String,
    soldOn: json['sold_on'] == null
        ? null
        : DateTime.parse(json['sold_on'] as String),
    areaM2: (json['area_m2'] as num?)?.toDouble(),
    landM2: _int(json['land_m2']),
    priceEur: (json['price_eur'] as num).toInt(),
    excluded: json['excluded'] == true,
  );

  final String street;
  final DateTime? soldOn;
  final double? areaM2;
  final int? landM2;
  final int priceEur;

  /// Excluded by the expert (e.g. atypical property).
  final bool excluded;

  /// Price per m², when the area is known.
  int? get priceM2Eur {
    final area = areaM2;
    return area == null || area <= 0 ? null : (priceEur / area).round();
  }

  @override
  List<Object?> get props => [
    street,
    soldOn,
    areaM2,
    landM2,
    priceEur,
    excluded,
  ];
}

/// A listing competing with the property.
class ValuationCompetitor extends Equatable {
  const new({
    required this.label,
    this.priceEur,
    this.note,
    this.daysOnline,
    this.retained = true,
  });

  factory fromJson(Map<String, dynamic> json) => ValuationCompetitor(
    label: json['label'] as String,
    priceEur: _int(json['price_eur']),
    note: _text(json['note']),
    daysOnline: _int(json['days_online']),
    retained: json['retained'] != false,
  );

  /// e.g. "T5 · 113 m²".
  final String label;
  final int? priceEur;
  final String? note;
  final int? daysOnline;
  final bool retained;

  @override
  List<Object?> get props => [label, priceEur, note, daysOnline, retained];
}

/// Role of a [ValuationAmountLine].
enum ValuationLineKind {
  /// Starting value.
  base,

  /// A line (adjustment or method).
  line,

  /// Result of the lines above.
  total,

  /// Cross-check (e.g. the AI trend).
  control;

  static ValuationLineKind parse(Object? value) =>
      values.firstWhere((kind) => kind.name == value, orElse: () => line);
}

/// A labelled amount ("Ce qui déplace le prix", "La méthode").
class ValuationAmountLine extends Equatable {
  const new({
    required this.label,
    required this.amountEur,
    this.kind = ValuationLineKind.line,
  });

  factory fromJson(Map<String, dynamic> json) => ValuationAmountLine(
    label: json['label'] as String,
    amountEur: (json['amount_eur'] as num).toInt(),
    kind: ValuationLineKind.parse(json['kind']),
  );

  final String label;
  final int amountEur;
  final ValuationLineKind kind;

  @override
  List<Object?> get props => [label, amountEur, kind];
}

int? _int(Object? value) => (value as num?)?.toInt();

String? _text(Object? value) {
  final text = (value as String?)?.trim();
  return text == null || text.isEmpty ? null : text;
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) return const [];
  final items = <T>[];
  for (final item in value) {
    if (item is! Map<String, dynamic>) continue;
    try {
      items.add(parse(item));
    } on Object {
      // Malformed entry typed by staff: skipped.
    }
  }
  return List.unmodifiable(items);
}
