part of 'property_context_cubit.dart';

/// Why a V3 answer is not accepted.
enum PropertyContextError {
  /// A required answer is missing.
  required,

  /// The year is not between [PropertyContextState.minYear] and this year.
  yearRange,

  /// The amount is not between [PropertyContextState.minAmount] and
  /// [PropertyContextState.maxAmount].
  amountRange,

  /// The month is not a valid `mm/aaaa` month.
  monthFormat,

  /// The month is before [PropertyContextState.minYear].
  monthTooEarly,

  /// The month is in the future.
  monthFuture,

  /// The number of dwellings is not between [PropertyContextState.minUnits]
  /// and [PropertyContextState.maxUnits].
  unitsRange,
}

/// Progress of "Continuer": the previous estimates are saved first, then
/// the view hands the answers to the tunnel cubit.
enum PropertyContextSubmission { idle, inProgress, success, failure }

/// A previous agency estimate as typed in its card.
final class EstimateDraft extends Equatable {
  const new({
    required this.key,
    this.id,
    this.price = '',
    this.month = '',
    this.agency = '',
    this.pendingId,
  });

  /// Identifies the card while it is edited (stable across saves).
  final int key;

  /// Id of the saved row, null until saved.
  final String? id;

  /// Amount as typed ("510 000").
  final String price;

  /// Month as typed (`mm/aaaa`).
  final String month;

  final String agency;

  /// The pending answer this card was pre-filled from (EPIC-16: an
  /// estimate said on another step, « À confirmer »).
  final String? pendingId;

  EstimateDraft copyWith({String? price, String? month, String? agency}) {
    return EstimateDraft(
      key: key,
      id: id,
      price: price ?? this.price,
      month: month ?? this.month,
      agency: agency ?? this.agency,
      pendingId: pendingId,
    );
  }

  /// This draft with the [id] of its saved row.
  EstimateDraft withId(String? id) => EstimateDraft(
    key: key,
    id: id,
    price: price,
    month: month,
    agency: agency,
    pendingId: pendingId,
  );

  @override
  List<Object?> get props => [key, id, price, month, agency, pendingId];
}

/// Answers of V3 · Contexte & type de bien, as edited.
final class PropertyContextState extends Equatable {
  const new({
    required this.today,
    this.propertyType,
    this.propertyTypeOther = '',
    this.landKind,
    this.parkingKind,
    this.commercialUse = '',
    this.unitsCount = '',
    this.purchaseYear = '',
    this.purchasePrice = '',
    this.selfBuilt,
    this.saleReason,
    this.previouslyEstimated,
    this.estimates = const [],
    this.savedEstimates = const [],
    this.estimateResolutions = const {},
    this.showErrors = false,
    this.submitAttempts = 0,
    this.submission = PropertyContextSubmission.idle,
    this.dictated = const {},
  });

  /// Earliest purchase year or estimate month accepted.
  static const minYear = 1900;

  /// Accepted range of amounts (€).
  static const minAmount = 1000;
  static const maxAmount = 100000000;

  /// Maximum length of the free texts.
  static const maxOtherTypeLength = 100;
  static const maxCommercialUseLength = 100;

  /// Accepted number of dwellings of a building.
  static const minUnits = 2;
  static const maxUnits = 500;
  static const maxAgencyLength = 120;

  /// Reference date for the "not in the future" checks.
  final DateTime today;

  final PropertyType? propertyType;

  /// Precision of an outbuilding or of "Autre" (free text).
  final String propertyTypeOther;

  /// Terrain: constructible or not.
  final LandKind? landKind;

  /// Garage / parking: its kind.
  final ParkingKind? parkingKind;

  /// Local commercial: its use, as typed.
  final String commercialUse;

  /// Immeuble: number of dwellings, as typed.
  final String unitsCount;

  /// Year as typed.
  final String purchaseYear;

  /// Amount as typed ("320 000").
  final String purchasePrice;

  final bool? selfBuilt;
  final SaleReason? saleReason;
  final bool? previouslyEstimated;

  /// Cards of previous estimates (shown when [previouslyEstimated]).
  final List<EstimateDraft> estimates;

  /// The estimates as saved by the last successful submission.
  final List<PreviousEstimate> savedEstimates;

  /// The pending estimates of the cards, resolved by the last submission
  /// (EPIC-16): closed once the step is saved.
  final Map<PendingResolution, List<String>> estimateResolutions;

  /// Whether errors are shown (after a first "Continuer").
  final bool showErrors;

  /// Incremented on each rejected "Continuer" (to reveal the first error).
  final int submitAttempts;

  final PropertyContextSubmission submission;

  /// Columns (and `estimate:<key>` cards) answered by voice on this visit
  /// ("Dicté").
  final Set<String> dictated;

  /// How the tunnel adapts to the selected type.
  PropertyTypeProfile get profile => PropertyTypeProfile.of(propertyType);

  /// The precision asked with the selected type.
  PropertyTypeDetail get detail => profile.detail;

  /// "Construit par vous ?" (not for land, parkings, commercial premises
  /// nor whole buildings).
  bool get asksSelfBuilt => profile.asksSelfBuilt;

  /// The number of dwellings is optional; when typed it must be between
  /// [minUnits] and [maxUnits].
  PropertyContextError? get unitsCountError {
    if (detail != PropertyTypeDetail.unitsCount) return null;
    final units = parseDigits(unitsCount);
    return units == null || (units >= minUnits && units <= maxUnits)
        ? null
        : PropertyContextError.unitsRange;
  }

  PropertyContextError? get propertyTypeError =>
      propertyType == null ? PropertyContextError.required : null;

  PropertyContextError? get purchaseYearError {
    final year = parseDigits(purchaseYear);
    if (year == null) return PropertyContextError.required;
    if (year < minYear || year > today.year) {
      return PropertyContextError.yearRange;
    }
    return null;
  }

  PropertyContextError? get purchasePriceError {
    final price = parseDigits(purchasePrice);
    return price == null ? null : _amountError(price);
  }

  PropertyContextError? get selfBuiltError =>
      asksSelfBuilt && selfBuilt == null ? PropertyContextError.required : null;

  PropertyContextError? estimatePriceError(EstimateDraft draft) {
    final price = parseDigits(draft.price);
    return price == null ? PropertyContextError.required : _amountError(price);
  }

  PropertyContextError? estimateMonthError(EstimateDraft draft) {
    if (draft.month.trim().isEmpty) return null;
    final month = parseMonth(draft.month);
    if (month == null) return PropertyContextError.monthFormat;
    if (month.year < minYear) return PropertyContextError.monthTooEarly;
    if (month.isAfter(DateTime(today.year, today.month))) {
      return PropertyContextError.monthFuture;
    }
    return null;
  }

  /// Whether the estimate cards are shown and saved.
  bool get hasEstimates => previouslyEstimated ?? false;

  bool get isValid =>
      propertyTypeError == null &&
      purchaseYearError == null &&
      purchasePriceError == null &&
      selfBuiltError == null &&
      unitsCountError == null &&
      (!hasEstimates ||
          estimates.every(
            (draft) =>
                estimatePriceError(draft) == null &&
                estimateMonthError(draft) == null,
          ));

  /// The `properties` columns of this step. The answers this type does
  /// not ask are left as they are (hidden, cleared when the dossier is
  /// sent: the seller may come back to the previous type).
  Map<String, Object?> get patch {
    String? text(String value) => value.trim().isEmpty ? null : value.trim();
    return {
      PropertyColumns.propertyType: propertyType,
      ...switch (detail) {
        PropertyTypeDetail.none => const {},
        PropertyTypeDetail.otherText => {
          PropertyColumns.propertyTypeOther: text(propertyTypeOther),
        },
        PropertyTypeDetail.landKind => {PropertyColumns.landKind: landKind},
        PropertyTypeDetail.parkingKind => {
          PropertyColumns.parkingKind: parkingKind,
        },
        PropertyTypeDetail.commercialUse => {
          PropertyColumns.commercialUse: text(commercialUse),
        },
        PropertyTypeDetail.unitsCount => {
          PropertyColumns.unitsCount: parseDigits(unitsCount),
        },
      },
      PropertyColumns.purchaseYear: parseDigits(purchaseYear),
      PropertyColumns.purchasePriceEur: parseDigits(purchasePrice),
      if (asksSelfBuilt) PropertyColumns.selfBuilt: selfBuilt,
      PropertyColumns.saleReason: saleReason,
      PropertyColumns.previouslyEstimated: previouslyEstimated,
    };
  }

  static PropertyContextError? _amountError(int amount) =>
      amount < minAmount || amount > maxAmount
      ? PropertyContextError.amountRange
      : null;

  /// The number made of the digits of [text], or null when it has none.
  static int? parseDigits(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : int.parse(digits);
  }

  /// The month of a `mm/aaaa` [text], or null when it is not one.
  static DateTime? parseMonth(String text) {
    final match = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(text.trim());
    if (match == null) return null;
    final month = int.parse(match.group(1)!);
    final year = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    return DateTime(year, month);
  }

  /// [month] as typed in an estimate card (`mm/aaaa`).
  static String formatMonth(DateTime month) =>
      '${month.month.toString().padLeft(2, '0')}/${month.year}';

  PropertyContextState copyWith({
    PropertyType? propertyType,
    String? propertyTypeOther,
    LandKind? Function()? landKind,
    ParkingKind? Function()? parkingKind,
    String? commercialUse,
    String? unitsCount,
    String? purchaseYear,
    String? purchasePrice,
    bool? selfBuilt,
    SaleReason? Function()? saleReason,
    bool? previouslyEstimated,
    List<EstimateDraft>? estimates,
    List<PreviousEstimate>? savedEstimates,
    Map<PendingResolution, List<String>>? estimateResolutions,
    bool? showErrors,
    int? submitAttempts,
    PropertyContextSubmission? submission,
    Set<String>? dictated,
  }) {
    return PropertyContextState(
      today: today,
      propertyType: propertyType ?? this.propertyType,
      propertyTypeOther: propertyTypeOther ?? this.propertyTypeOther,
      landKind: landKind == null ? this.landKind : landKind(),
      parkingKind: parkingKind == null ? this.parkingKind : parkingKind(),
      commercialUse: commercialUse ?? this.commercialUse,
      unitsCount: unitsCount ?? this.unitsCount,
      purchaseYear: purchaseYear ?? this.purchaseYear,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      selfBuilt: selfBuilt ?? this.selfBuilt,
      saleReason: saleReason == null ? this.saleReason : saleReason(),
      previouslyEstimated: previouslyEstimated ?? this.previouslyEstimated,
      estimates: estimates ?? this.estimates,
      savedEstimates: savedEstimates ?? this.savedEstimates,
      estimateResolutions: estimateResolutions ?? this.estimateResolutions,
      showErrors: showErrors ?? this.showErrors,
      submitAttempts: submitAttempts ?? this.submitAttempts,
      submission: submission ?? this.submission,
      dictated: dictated ?? this.dictated,
    );
  }

  @override
  List<Object?> get props => [
    today,
    propertyType,
    propertyTypeOther,
    landKind,
    parkingKind,
    commercialUse,
    unitsCount,
    purchaseYear,
    purchasePrice,
    selfBuilt,
    saleReason,
    previouslyEstimated,
    estimates,
    savedEstimates,
    estimateResolutions,
    showErrors,
    submitAttempts,
    submission,
    dictated,
  ];
}
