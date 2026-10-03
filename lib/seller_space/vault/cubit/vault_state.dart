part of 'vault_cubit.dart';

enum VaultStatus { initial, loading, success, failure }

/// What the vault shows: one property, or a sale lot.
final class VaultTarget extends Equatable {
  const new property(String this.propertyId) : lotId = null;

  const new lot(String this.lotId) : propertyId = null;

  final String? propertyId;
  final String? lotId;

  bool get isLot => lotId != null;

  @override
  List<Object?> get props => [propertyId, lotId];
}

/// Feedback of an action, shown once as a snack bar.
enum VaultNotice {
  uploaded,
  uploadFailed,
  replaced,
  deleted,
  deleteFailed,
  saveFailed,
  openFailed,
  shareFailed,
  unsupportedType,
  fileTooLarge,
  metadataUnremovable,
  accessDenied,
  pickFailed,
  reuseFailed,
}

/// Where a new document goes.
final class VaultAddTarget extends Equatable {
  const new({required this.propertyId, required this.kind, this.ownerRef});

  final String propertyId;
  final DocumentKind kind;

  /// The owner of an identity document.
  final String? ownerRef;

  @override
  List<Object?> get props => [propertyId, kind, ownerRef];
}

/// An upload that failed, kept to retry it ("Réessayer").
final class VaultFailedUpload extends Equatable {
  const new({required this.target, required this.file, this.replacing});

  final VaultAddTarget target;
  final PickedDocument file;

  /// The document it replaces, if any.
  final PropertyDocument? replacing;

  @override
  List<Object?> get props => [target, file, replacing];
}

final class VaultState extends Equatable {
  const new({
    this.status = VaultStatus.initial,
    this.target,
    this.properties = const [],
    this.documents = const [],
    this.owners = const {},
    this.valuations = const {},
    this.busy = false,
    this.busyDocumentIds = const {},
    this.failedUpload,
    this.notice,
  });

  final VaultStatus status;
  final VaultTarget? target;

  /// The properties shown (one, or the members of the lot).
  final List<Property> properties;

  /// Their documents, oldest first.
  final List<PropertyDocument> documents;

  /// Their owners, by property id.
  final Map<String, List<PropertyOwner>> owners;

  /// Their latest certified valuation, by property id.
  final Map<String, Valuation> valuations;

  /// A document is being added (picked, scanned, uploaded).
  final bool busy;

  /// Documents being changed (renamed, shared, deleted, opened…).
  final Set<String> busyDocumentIds;

  final VaultFailedUpload? failedUpload;

  /// Feedback of the last action (cleared by [VaultCubit.noticeShown]).
  final VaultNotice? notice;

  /// The rubrics, documents and missing ones.
  VaultContents get contents => VaultContents.of(
    properties: properties,
    documents: documents,
    owners: owners,
    valuations: valuations,
  );

  /// The property [id] among the shown ones.
  Property? propertyById(String id) {
    for (final property in properties) {
      if (property.id == id) return property;
    }
    return null;
  }

  /// The document [id], with its latest values.
  PropertyDocument? documentById(String id) {
    for (final document in documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  VaultState copyWith({
    VaultStatus? status,
    VaultTarget? target,
    List<Property>? properties,
    List<PropertyDocument>? documents,
    Map<String, List<PropertyOwner>>? owners,
    Map<String, Valuation>? valuations,
    bool? busy,
    Set<String>? busyDocumentIds,
    VaultFailedUpload? Function()? failedUpload,
    VaultNotice? Function()? notice,
  }) => VaultState(
    status: status ?? this.status,
    target: target ?? this.target,
    properties: properties ?? this.properties,
    documents: documents ?? this.documents,
    owners: owners ?? this.owners,
    valuations: valuations ?? this.valuations,
    busy: busy ?? this.busy,
    busyDocumentIds: busyDocumentIds ?? this.busyDocumentIds,
    failedUpload: failedUpload == null ? this.failedUpload : failedUpload(),
    notice: notice == null ? this.notice : notice(),
  );

  @override
  List<Object?> get props => [
    status,
    target,
    properties,
    documents,
    owners,
    valuations,
    busy,
    busyDocumentIds,
    failedUpload,
    notice,
  ];
}
