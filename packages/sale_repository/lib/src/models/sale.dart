import 'package:equatable/equatable.dart';

/// A value stored as text in the database.
abstract interface class SaleDbEnum {
  String get value;
}

T? _parse<T extends SaleDbEnum>(List<T> values, Object? value) {
  for (final candidate in values) {
    if (candidate.value == value) return candidate;
  }
  return null;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

int? _int(Object? value) => (value as num?)?.toInt();

/// The three formulas (`sales.formula`): the single source of their rates
/// and indicative prices in the app (mirror of the SQL checks).
enum SaleFormula implements SaleDbEnum {
  /// L’Essentiel · 1 % au succès, no fee.
  essentiel('essentiel', 1),

  /// Le Premium · 1 % au succès + 299 € de frais de dossier + 99 €/mois
  /// (indicative: nothing is charged in the app in v1).
  premium('premium', 1),

  /// L’Expert · 3 % au succès, 3-month exclusive mandate, agent.
  expert('expert', 3);

  new(this.value, this.feePercent);

  @override
  final String value;

  /// Success fee, in percent of the sale price.
  final int feePercent;

  /// Indicative set-up fee of Le Premium (TTC).
  static const premiumSetupFeeEur = 299;

  /// Indicative monthly fee of Le Premium (TTC).
  static const premiumMonthlyFeeEur = 99;

  /// Duration of the Expert mandate, in months.
  static const expertDurationMonths = 3;

  /// Whether the seller prepares and publishes the listing (V11a).
  bool get selfPublished => this != expert;

  /// The fee on a sale at [priceEur], rounded to 10 €.
  int commissionOn(int priceEur) => (priceEur * feePercent / 1000).round() * 10;

  static SaleFormula? parse(Object? value) => _parse(values, value);
}

/// Where a sale stands (`sales.stage`).
enum SaleStage implements SaleDbEnum {
  /// The formula is chosen; the mandate is not signed yet.
  planChosen('plan_chosen'),

  /// The test mandate is signed; the listing is being prepared (offline).
  mandateSigned('mandate_signed'),

  /// The listing is online in Realesty.
  published('published'),

  /// The seller withdrew the sale.
  withdrawn('withdrawn');

  new(this.value);

  @override
  final String value;

  bool get isActive => this != withdrawn;

  static SaleStage parse(Object? value) =>
      _parse(values, value) ?? SaleStage.planChosen;
}

/// Who wrote the listing text (`sales.description_source`).
enum DescriptionSource implements SaleDbEnum {
  template('template'),
  ai('ai'),
  seller('seller');

  new(this.value);

  @override
  final String value;

  static DescriptionSource? parse(Object? value) => _parse(values, value);
}

/// Column names of the `sales` table.
abstract final class SaleColumns {
  static const id = 'id';
  static const ownerId = 'owner_id';
  static const propertyId = 'property_id';
  static const lotId = 'lot_id';
  static const formula = 'formula';
  static const stage = 'stage';
  static const askingPriceEur = 'asking_price_eur';
  static const listingTitle = 'listing_title';
  static const listingDescription = 'listing_description';
  static const descriptionSource = 'description_source';
  static const aiRetouchWanted = 'ai_retouch_wanted';
  static const homeStagingWanted = 'home_staging_wanted';
  static const photosImportedAt = 'photos_imported_at';
  static const isTest = 'is_test';
  static const formulaChosenAt = 'formula_chosen_at';
  static const mandateSignedAt = 'mandate_signed_at';
  static const publishedAt = 'published_at';
  static const withdrawnAt = 'withdrawn_at';
  static const createdAt = 'created_at';
}

/// A sale (`sales`): of one property ([propertyId]) or of a sale lot
/// ([lotId]).
class Sale extends Equatable {
  const new({
    required this.id,
    required this.formula,
    required this.stage,
    this.ownerId,
    this.propertyId,
    this.lotId,
    this.askingPriceEur,
    this.listingTitle,
    this.listingDescription,
    this.descriptionSource,
    this.aiRetouchWanted = false,
    this.homeStagingWanted = false,
    this.photosImportedAt,
    this.isTest = true,
    this.formulaChosenAt,
    this.mandateSignedAt,
    this.publishedAt,
    this.withdrawnAt,
    this.createdAt,
  });

  factory fromJson(Map<String, dynamic> json) => Sale(
    id: json[SaleColumns.id] as String,
    ownerId: json[SaleColumns.ownerId] as String?,
    propertyId: json[SaleColumns.propertyId] as String?,
    lotId: json[SaleColumns.lotId] as String?,
    formula:
        SaleFormula.parse(json[SaleColumns.formula]) ?? SaleFormula.essentiel,
    stage: SaleStage.parse(json[SaleColumns.stage]),
    askingPriceEur: _int(json[SaleColumns.askingPriceEur]),
    listingTitle: json[SaleColumns.listingTitle] as String?,
    listingDescription: json[SaleColumns.listingDescription] as String?,
    descriptionSource: DescriptionSource.parse(
      json[SaleColumns.descriptionSource],
    ),
    aiRetouchWanted: json[SaleColumns.aiRetouchWanted] == true,
    homeStagingWanted: json[SaleColumns.homeStagingWanted] == true,
    photosImportedAt: _date(json[SaleColumns.photosImportedAt]),
    isTest: json[SaleColumns.isTest] != false,
    formulaChosenAt: _date(json[SaleColumns.formulaChosenAt]),
    mandateSignedAt: _date(json[SaleColumns.mandateSignedAt]),
    publishedAt: _date(json[SaleColumns.publishedAt]),
    withdrawnAt: _date(json[SaleColumns.withdrawnAt]),
    createdAt: _date(json[SaleColumns.createdAt]),
  );

  final String id;
  final String? ownerId;
  final String? propertyId;
  final String? lotId;
  final SaleFormula formula;
  final SaleStage stage;
  final int? askingPriceEur;
  final String? listingTitle;
  final String? listingDescription;
  final DescriptionSource? descriptionSource;
  final bool aiRetouchWanted;
  final bool homeStagingWanted;
  final DateTime? photosImportedAt;
  final bool isTest;
  final DateTime? formulaChosenAt;
  final DateTime? mandateSignedAt;
  final DateTime? publishedAt;
  final DateTime? withdrawnAt;
  final DateTime? createdAt;

  /// Whether the sale is about a sale lot.
  bool get isLot => lotId != null;

  /// Whether the mandate is signed (and the sale not withdrawn).
  bool get isSigned =>
      stage == SaleStage.mandateSigned || stage == SaleStage.published;

  @override
  List<Object?> get props => [
    id,
    ownerId,
    propertyId,
    lotId,
    formula,
    stage,
    askingPriceEur,
    listingTitle,
    listingDescription,
    descriptionSource,
    aiRetouchWanted,
    homeStagingWanted,
    photosImportedAt,
    isTest,
    formulaChosenAt,
    mandateSignedAt,
    publishedAt,
    withdrawnAt,
    createdAt,
  ];
}

/// Status of a [Mandate].
enum MandateStatus implements SaleDbEnum {
  signed('signed'),
  terminated('terminated');

  new(this.value);

  @override
  final String value;
}

/// A signed TEST mandate (`mandates`).
class Mandate extends Equatable {
  const new({
    required this.id,
    required this.saleId,
    required this.formula,
    required this.signedAt,
    this.status = MandateStatus.signed,
    this.termsVersion,
    this.presentationPriceEur,
    this.feeRate,
    this.durationMonths,
    this.isTest = true,
    this.documentPath,
    this.terminatedAt,
  });

  factory fromJson(Map<String, dynamic> json) => Mandate(
    id: json['id'] as String,
    saleId: json['sale_id'] as String,
    formula: SaleFormula.parse(json['formula']) ?? SaleFormula.essentiel,
    status:
        _parse(MandateStatus.values, json['status']) ?? MandateStatus.signed,
    termsVersion: json['terms_version'] as String?,
    presentationPriceEur: _int(json['presentation_price_eur']),
    feeRate: (json['fee_rate'] as num?)?.toDouble(),
    durationMonths: _int(json['duration_months']),
    isTest: json['is_test'] != false,
    documentPath: json['document_path'] as String?,
    signedAt: DateTime.parse(json['signed_at'] as String),
    terminatedAt: _date(json['terminated_at']),
  );

  final String id;
  final String saleId;
  final SaleFormula formula;
  final MandateStatus status;
  final String? termsVersion;
  final int? presentationPriceEur;
  final double? feeRate;
  final int? durationMonths;
  final bool isTest;

  /// Path of the PDF in `sale-documents` (null until rendered).
  final String? documentPath;
  final DateTime signedAt;
  final DateTime? terminatedAt;

  @override
  List<Object?> get props => [
    id,
    saleId,
    formula,
    status,
    termsVersion,
    presentationPriceEur,
    feeRate,
    durationMonths,
    isTest,
    documentPath,
    signedAt,
    terminatedAt,
  ];
}

/// A service asked without payment (`sale_requests.kind`).
enum SaleRequestKind implements SaleDbEnum {
  /// Le Premium: a Realesty adviser calls back to set it up.
  premiumSetup('premium_setup', SaleFormula.premiumSetupFeeEur),
  shootingPhoto('shooting_photo', 200),
  shootingPhotoVideo('shooting_photo_video', 350),
  diagnostics('diagnostics', 250);

  new(this.value, this.priceEurTtc);

  @override
  final String value;

  /// Indicative price (TTC); nothing is charged in the app.
  final int priceEurTtc;

  bool get isShooting => this == shootingPhoto || this == shootingPhotoVideo;
}

/// Status of a [SaleRequest].
enum SaleRequestStatus implements SaleDbEnum {
  requested('requested'),
  scheduled('scheduled'),
  done('done'),
  cancelled('cancelled');

  new(this.value);

  @override
  final String value;

  bool get isOpen => this == requested || this == scheduled;
}

/// A mandatory diagnostic (`sale_requests.diagnostics`).
enum Diagnostic implements SaleDbEnum {
  dpe('dpe'),
  electricity('electricite'),
  gas('gaz'),
  asbestos('amiante'),
  lead('plomb'),
  termites('termites'),
  risks('erp');

  new(this.value);

  @override
  final String value;
}

/// A service request of a sale (`sale_requests`).
class SaleRequest extends Equatable {
  const new({
    required this.id,
    required this.saleId,
    required this.kind,
    this.status = SaleRequestStatus.requested,
    this.diagnostics = const [],
    this.preferredSlots = const [],
    this.scheduledAt,
    this.priceEurTtc,
    this.createdAt,
  });

  factory fromJson(Map<String, dynamic> json) => SaleRequest(
    id: json['id'] as String,
    saleId: json['sale_id'] as String,
    kind:
        _parse(SaleRequestKind.values, json['kind']) ??
        SaleRequestKind.premiumSetup,
    status:
        _parse(SaleRequestStatus.values, json['status']) ??
        SaleRequestStatus.requested,
    diagnostics: [
      for (final value in (json['diagnostics'] as List?) ?? const [])
        ?_parse(Diagnostic.values, value),
    ],
    preferredSlots: [
      for (final value in (json['preferred_slots'] as List?) ?? const [])
        DateTime.parse(value as String),
    ],
    scheduledAt: _date(json['scheduled_at']),
    priceEurTtc: _int(json['price_eur_ttc']),
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String saleId;
  final SaleRequestKind kind;
  final SaleRequestStatus status;
  final List<Diagnostic> diagnostics;
  final List<DateTime> preferredSlots;
  final DateTime? scheduledAt;
  final int? priceEurTtc;
  final DateTime? createdAt;

  @override
  List<Object?> get props => [
    id,
    saleId,
    kind,
    status,
    diagnostics,
    preferredSlots,
    scheduledAt,
    priceEurTtc,
    createdAt,
  ];
}

/// A photo of a listing (`listing_photos`, files in `listing-media`). The
/// first one (by [sortOrder]) is the cover.
class ListingPhoto extends Equatable {
  const new({
    required this.id,
    required this.saleId,
    required this.storagePath,
    this.propertyId,
    this.roomId,
    this.sourceRoomPhotoId,
    this.width,
    this.height,
    this.sizeBytes,
    this.sortOrder = 0,
    this.caption,
  });

  factory fromJson(Map<String, dynamic> json) => ListingPhoto(
    id: json['id'] as String,
    saleId: json['sale_id'] as String,
    storagePath: json['storage_path'] as String,
    propertyId: json['property_id'] as String?,
    roomId: json['room_id'] as String?,
    sourceRoomPhotoId: json['source_room_photo_id'] as String?,
    width: _int(json['width']),
    height: _int(json['height']),
    sizeBytes: _int(json['size_bytes']),
    sortOrder: _int(json['sort_order']) ?? 0,
    caption: json['caption'] as String?,
  );

  final String id;
  final String saleId;
  final String storagePath;
  final String? propertyId;
  final String? roomId;

  /// The dossier photo it was copied from, if any.
  final String? sourceRoomPhotoId;
  final int? width;
  final int? height;
  final int? sizeBytes;
  final int sortOrder;
  final String? caption;

  Map<String, Object?> toJson() => {
    'id': id,
    'sale_id': saleId,
    'storage_path': storagePath,
    'property_id': propertyId,
    'room_id': roomId,
    'source_room_photo_id': sourceRoomPhotoId,
    'width': width,
    'height': height,
    'size_bytes': sizeBytes,
    'sort_order': sortOrder,
    'caption': caption,
  };

  @override
  List<Object?> get props => [
    id,
    saleId,
    storagePath,
    propertyId,
    roomId,
    sourceRoomPhotoId,
    width,
    height,
    sizeBytes,
    sortOrder,
    caption,
  ];
}
