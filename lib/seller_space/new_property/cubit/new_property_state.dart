part of 'new_property_cubit.dart';

/// Progress of "Commencer l’audit".
enum NewPropertyStatus {
  idle,
  inProgress,

  /// Created (and pre-filled): `property` is set.
  success,

  /// Nothing created, or the creation failed.
  failure,

  /// Created, but copying the owners or the identity document failed (a
  /// new tap retries the copy only).
  copyFailure,

  /// The seller already has the maximum number of properties.
  limitReached,
}

/// Answers of "Ajouter un bien" (EPIC-13).
final class NewPropertyState extends Equatable {
  const new({
    required this.properties,
    this.type,
    this.partnerId,
    this.sourceId,
    this.reuseOwners = true,
    this.reuseIdentity = true,
    this.showErrors = false,
    this.submitAttempts = 0,
    this.status = NewPropertyStatus.idle,
    this.property,
    this.lot,
  });

  /// The seller's existing properties, oldest first.
  final List<Property> properties;

  final PropertyType? type;

  /// The property the new one is sold with (lot), if any.
  final String? partnerId;

  /// The property to copy the owners and identity document from; by
  /// default the partner, else the most recent property.
  final String? sourceId;
  final bool reuseOwners;
  final bool reuseIdentity;

  final bool showErrors;

  /// Incremented on each rejected submission (to reveal the error).
  final int submitAttempts;
  final NewPropertyStatus status;

  /// The created property, once created.
  final Property? property;

  /// The lot created or joined, if any.
  final PropertyLot? lot;

  /// The properties the new one can be sold with: none in a lot already
  /// taken over by an expert.
  List<Property> get partners => [
    for (final property in properties)
      if (property.status != PropertyStatus.inReview &&
          property.status != PropertyStatus.certified)
        property,
  ];

  Property? get partner => _byId(partnerId);

  /// The property the information is copied from.
  Property? get source => _byId(sourceId) ?? partner ?? properties.lastOrNull;

  Property? _byId(String? id) {
    for (final property in properties) {
      if (property.id == id) return property;
    }
    return null;
  }

  bool get typeMissing => type == null;

  bool get isBusy => status == NewPropertyStatus.inProgress;

  NewPropertyState copyWith({
    PropertyType? type,
    String? Function()? partnerId,
    String? sourceId,
    bool? reuseOwners,
    bool? reuseIdentity,
    bool? showErrors,
    int? submitAttempts,
    NewPropertyStatus? status,
    Property? property,
    PropertyLot? lot,
  }) {
    return NewPropertyState(
      properties: properties,
      type: type ?? this.type,
      partnerId: partnerId == null ? this.partnerId : partnerId(),
      sourceId: sourceId ?? this.sourceId,
      reuseOwners: reuseOwners ?? this.reuseOwners,
      reuseIdentity: reuseIdentity ?? this.reuseIdentity,
      showErrors: showErrors ?? this.showErrors,
      submitAttempts: submitAttempts ?? this.submitAttempts,
      status: status ?? this.status,
      property: property ?? this.property,
      lot: lot ?? this.lot,
    );
  }

  @override
  List<Object?> get props => [
    properties,
    type,
    partnerId,
    sourceId,
    reuseOwners,
    reuseIdentity,
    showErrors,
    submitAttempts,
    status,
    property,
    lot,
  ];
}
