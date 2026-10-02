import 'package:equatable/equatable.dart';
import 'package:property_repository/src/models/enums.dart';
import 'package:property_repository/src/models/json.dart';

/// State of a non-certified estimate (`market_snapshots.status`).
enum MarketSnapshotStatus implements DbEnum {
  /// Being computed by the `estimate-property` Edge Function.
  running('running'),

  /// Estimate available.
  ok('ok'),

  /// No estimate (fewer than 5 comparable sales, unsupported property…):
  /// the expert takes over.
  insufficient('insufficient'),

  /// The computation failed; it can be requested again.
  error('error');

  new(this.value);

  @override
  final String value;
}

/// Area of the comparable sales (`market_snapshots.scope`).
enum MarketScope implements DbEnum {
  /// Within `radiusM` of the property.
  radius('radius'),

  /// The whole commune (arrondissement in Paris, Lyon, Marseille).
  commune('commune');

  new(this.value);

  @override
  final String value;
}

/// Level of the confidence index (0–100) of an estimate.
enum EstimateConfidenceLevel {
  /// 70 and above.
  high,

  /// 40 to 69.
  medium,

  /// Below 40.
  low;

  /// Level of a [score] (0–100).
  static EstimateConfidenceLevel of(int score) => score >= 70
      ? high
      : score >= 40
      ? medium
      : low;
}

/// {@template comparable_sale}
/// A DVF sale used for the estimate. The street is only known when at
/// least 3 sales are recorded in it (never the house number).
/// {@endtemplate}
class ComparableSale extends Equatable {
  /// {@macro comparable_sale}
  const new({
    required this.propertyType,
    required this.areaM2,
    required this.soldYear,
    required this.priceEur,
    required this.priceM2Eur,
    this.street,
    this.rooms,
    this.landM2,
    this.distanceM,
  });

  /// Builds a sale from an item of `market_snapshots.comparables`.
  factory fromJson(Map<String, dynamic> json) => ComparableSale(
    propertyType: parseDbEnum(PropertyType.values, json['type']),
    street: json['street'] as String?,
    areaM2: readInt(json['area_m2']) ?? 0,
    rooms: readInt(json['rooms']),
    landM2: readInt(json['land_m2']),
    soldYear: readInt(json['sold_year']) ?? 0,
    distanceM: readInt(json['distance_m']),
    priceEur: readInt(json['price_eur']) ?? 0,
    priceM2Eur: readInt(json['price_m2_eur']) ?? 0,
  );

  final PropertyType? propertyType;
  final String? street;
  final int areaM2;
  final int? rooms;
  final int? landM2;

  /// Year of the sale only (no month, for discretion).
  final int soldYear;

  /// Rounded distance to the property, null when unknown.
  final int? distanceM;
  final int priceEur;
  final int priceM2Eur;

  @override
  List<Object?> get props => [
    propertyType,
    street,
    areaM2,
    rooms,
    landM2,
    soldYear,
    distanceM,
    priceEur,
    priceM2Eur,
  ];
}

/// {@template market_factor}
/// A factor listed under « Ce qui influence votre estimation » (no figure
/// effect in v1).
/// {@endtemplate}
class MarketFactor extends Equatable {
  /// {@macro market_factor}
  const new({required this.positive, required this.label});

  /// Builds a factor from an item of `market_snapshots.factors`.
  factory fromJson(Map<String, dynamic> json) => MarketFactor(
    positive: json['sign'] != '-',
    label: json['label'] as String? ?? '',
  );

  final bool positive;

  /// French label (computed by the backend or entered by the seller).
  final String label;

  @override
  List<Object?> get props => [positive, label];
}

/// {@template semester_median}
/// Median price per m² of a half-year (curve kept for the expert / V9b).
/// {@endtemplate}
class SemesterMedian extends Equatable {
  /// {@macro semester_median}
  const new({
    required this.semester,
    required this.medianM2,
    required this.count,
  });

  /// Builds a point from an item of `market_snapshots.semester_medians`.
  factory fromJson(Map<String, dynamic> json) => SemesterMedian(
    semester: json['semester'] as String? ?? '',
    medianM2: readInt(json['median_m2']) ?? 0,
    count: readInt(json['count']) ?? 0,
  );

  /// `YYYY-S1` or `YYYY-S2`.
  final String semester;
  final int medianM2;
  final int count;

  @override
  List<Object?> get props => [semester, medianM2, count];
}

List<T> _readList<T>(
  Object? raw,
  T Function(Map<String, dynamic> json) fromJson,
) => [
  for (final item in raw as List<Object?>? ?? const [])
    if (item is Map<String, dynamic>) fromJson(item),
];

/// {@template market_snapshot}
/// Non-certified estimate of a property (`market_snapshots`), computed once
/// when the dossier is sent from the DVF sales of its sector. Read-only for
/// the app (written by the `estimate-property` Edge Function).
/// {@endtemplate}
class MarketSnapshot extends Equatable {
  /// {@macro market_snapshot}
  const new({
    required this.id,
    required this.propertyId,
    required this.status,
    required this.createdAt,
    this.reason,
    this.computedAt,
    this.dataUntil,
    this.propertyType,
    this.livingAreaM2,
    this.city,
    this.lowEur,
    this.medianEur,
    this.highEur,
    this.priceM2Low,
    this.priceM2Median,
    this.priceM2High,
    this.confidence,
    this.comparablesCount,
    this.scope,
    this.radiusM,
    this.months,
    this.sales12m,
    this.yoyChangePct,
    this.semesterMedians = const [],
    this.comparables = const [],
    this.factors = const [],
    this.explanation,
  });

  /// Builds a snapshot from a `market_snapshots` row.
  factory fromJson(Map<String, dynamic> json) => MarketSnapshot(
    id: json['id'] as String,
    propertyId: json['property_id'] as String,
    status:
        parseDbEnum(MarketSnapshotStatus.values, json['status']) ??
        MarketSnapshotStatus.error,
    reason: json['reason'] as String?,
    createdAt: readDateTime(json['created_at'])!,
    computedAt: readDateTime(json['computed_at']),
    dataUntil: readDateTime(json['data_until']),
    propertyType: parseDbEnum(PropertyType.values, json['property_type']),
    livingAreaM2: readDouble(json['living_area_m2']),
    city: json['city'] as String?,
    lowEur: readInt(json['estimate_low_eur']),
    medianEur: readInt(json['estimate_median_eur']),
    highEur: readInt(json['estimate_high_eur']),
    priceM2Low: readInt(json['price_m2_low']),
    priceM2Median: readInt(json['price_m2_median']),
    priceM2High: readInt(json['price_m2_high']),
    confidence: readInt(json['confidence']),
    comparablesCount: readInt(json['comparables_count']),
    scope: parseDbEnum(MarketScope.values, json['scope']),
    radiusM: readInt(json['radius_m']),
    months: readInt(json['months']),
    sales12m: readInt(json['sales_12m']),
    yoyChangePct: readDouble(json['yoy_change_pct']),
    semesterMedians: _readList(
      json['semester_medians'],
      SemesterMedian.fromJson,
    ),
    comparables: _readList(json['comparables'], ComparableSale.fromJson),
    factors: _readList(json['factors'], MarketFactor.fromJson),
    explanation: json['explanation_fr'] as String?,
  );

  final String id;
  final String propertyId;
  final MarketSnapshotStatus status;

  /// Why there is no estimate (status [MarketSnapshotStatus.insufficient]):
  /// `too_few_sales`, `unsupported_type`, `missing_area`,
  /// `missing_location` or `no_dvf_coverage`.
  final String? reason;
  final DateTime createdAt;
  final DateTime? computedAt;

  /// Date of the most recent DVF sale known when computing.
  final DateTime? dataUntil;
  final PropertyType? propertyType;
  final double? livingAreaM2;
  final String? city;
  final int? lowEur;
  final int? medianEur;
  final int? highEur;

  /// First quartile, median and third quartile of the sector's price per m²
  /// (comparables weighted by proximity and age, brought to today).
  final int? priceM2Low;
  final int? priceM2Median;
  final int? priceM2High;

  /// Confidence index, 0–100.
  final int? confidence;
  final int? comparablesCount;
  final MarketScope? scope;
  final int? radiusM;

  /// Period of the comparable sales (24, 36 or 60 months).
  final int? months;

  /// Sales of the property type in the commune over the last 12 months.
  final int? sales12m;

  /// Change of the median price per m² over one year (%).
  final double? yoyChangePct;
  final List<SemesterMedian> semesterMedians;

  /// Ordered by weight (most relevant first).
  final List<ComparableSale> comparables;
  final List<MarketFactor> factors;

  /// French explanation (written by the AI from the figures, or a template).
  final String? explanation;

  /// Whether this is the definitive result (never recomputed).
  bool get isFinal =>
      status == MarketSnapshotStatus.ok ||
      status == MarketSnapshotStatus.insufficient;

  /// Whether the search of comparables had to be widened beyond the
  /// neighbourhood (radius of 5 km or more) or the 2 most recent years.
  bool get isSearchWidened => (radiusM ?? 0) >= 5000 || (months ?? 0) > 24;

  /// Search period in years (2, 3 or 5), null when unknown.
  int? get years {
    final months = this.months;
    return months == null ? null : (months / 12).round();
  }

  /// Level of [confidence], null when unknown.
  EstimateConfidenceLevel? get confidenceLevel {
    final confidence = this.confidence;
    return confidence == null ? null : EstimateConfidenceLevel.of(confidence);
  }

  @override
  List<Object?> get props => [
    id,
    propertyId,
    status,
    reason,
    createdAt,
    computedAt,
    dataUntil,
    propertyType,
    livingAreaM2,
    city,
    lowEur,
    medianEur,
    highEur,
    priceM2Low,
    priceM2Median,
    priceM2High,
    confidence,
    comparablesCount,
    scope,
    radiusM,
    months,
    sales12m,
    yoyChangePct,
    semesterMedians,
    comparables,
    factors,
    explanation,
  ];
}
