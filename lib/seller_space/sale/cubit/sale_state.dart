part of 'sale_cubit.dart';

/// Loading of a sale.
enum SaleLoadStatus { loading, ready, notFound, failure }

/// An action of a sale screen in progress.
enum SaleAction {
  formula,
  sign,
  mandatePdf,
  request,
  listing,
  publish,
  withdraw,
}

/// A sale and its context (see [SaleCubit]).
final class SaleState extends Equatable {
  const new({
    this.status = SaleLoadStatus.loading,
    this.sale,
    this.mandate,
    this.requests = const [],
    this.members = const [],
    this.valuations = const {},
    this.owners = const [],
    this.identities = const {},
    this.documentKinds = const {},
    this.busy,
    this.failure,
    this.mandateUrl,
  });

  final SaleLoadStatus status;
  final Sale? sale;

  /// The latest mandate (signed, or terminated after a withdrawal).
  final Mandate? mandate;
  final List<SaleRequest> requests;

  /// The properties sold, the main one first.
  final List<Property> members;

  /// Certified valuations of the members, by property id.
  final Map<String, Valuation> valuations;

  /// Owners of the main property, in order.
  final List<PropertyOwner> owners;

  /// Identity verification by the team, by owner id.
  final Map<String, DateTime?> identities;

  /// Kinds of the documents of the main property.
  final Set<DocumentKind> documentKinds;
  final SaleAction? busy;

  /// What stopped the last action (null when it succeeded).
  final SaleFailure? failure;

  /// Temporary URL of the mandate PDF, once asked ([SaleCubit.openMandate]).
  final String? mandateUrl;

  /// The main property (the property sold, or the lot's main property).
  Property? get mainProperty => members.firstOrNull;

  /// Sum of the certified values of the members (null when none).
  int? get certifiedValue => _sum((v) => v.valueEur);

  /// Sum of the low bounds of the certified ranges.
  int? get certifiedLow => _sum((v) => v.lowEur);

  /// Sum of the high bounds of the certified ranges.
  int? get certifiedHigh => _sum((v) => v.highEur);

  int? _sum(int Function(Valuation) of) => valuations.isEmpty
      ? null
      : valuations.values.map(of).reduce((a, b) => a + b);

  /// The price the commission is computed on: the asking price, else the
  /// certified value.
  int? get basePrice => sale?.askingPriceEur ?? certifiedValue;

  /// The owner who signs: the one linked to the account, else the first.
  PropertyOwner? signerFor(String userId) =>
      owners.where((o) => o.profileId == userId).firstOrNull ??
      owners.firstOrNull;

  /// Whether the identity of [owner] was verified by the team.
  bool isVerified(PropertyOwner owner) => identities[owner.id] != null;

  /// Whether the main property has an identity document.
  bool get hasIdentityDocument =>
      documentKinds.contains(DocumentKind.identityDocument);

  /// Whether the main property has diagnostics in its dossier.
  bool get hasDiagnostics => documentKinds.contains(DocumentKind.diagnostics);

  /// The open request of [kind], if any.
  SaleRequest? openRequest(SaleRequestKind kind) =>
      requests.where((r) => r.kind == kind && r.status.isOpen).lastOrNull;

  /// The open photo shoot request, if any.
  SaleRequest? get openShooting =>
      openRequest(SaleRequestKind.shootingPhoto) ??
      openRequest(SaleRequestKind.shootingPhotoVideo);

  SaleState copyWith({
    SaleLoadStatus? status,
    Sale? sale,
    Mandate? mandate,
    bool clearMandate = false,
    List<SaleRequest>? requests,
    List<Property>? members,
    Map<String, Valuation>? valuations,
    List<PropertyOwner>? owners,
    Map<String, DateTime?>? identities,
    Set<DocumentKind>? documentKinds,
    SaleAction? busy,
    bool clearBusy = false,
    SaleFailure? failure,
    bool clearFailure = false,
    String? mandateUrl,
  }) => SaleState(
    status: status ?? this.status,
    sale: sale ?? this.sale,
    mandate: clearMandate ? null : mandate ?? this.mandate,
    requests: requests ?? this.requests,
    members: members ?? this.members,
    valuations: valuations ?? this.valuations,
    owners: owners ?? this.owners,
    identities: identities ?? this.identities,
    documentKinds: documentKinds ?? this.documentKinds,
    busy: clearBusy ? null : busy ?? this.busy,
    failure: clearFailure ? null : failure ?? this.failure,
    mandateUrl: mandateUrl ?? this.mandateUrl,
  );

  @override
  List<Object?> get props => [
    status,
    sale,
    mandate,
    requests,
    members,
    valuations,
    owners,
    identities,
    documentKinds,
    busy,
    failure,
    mandateUrl,
  ];
}
