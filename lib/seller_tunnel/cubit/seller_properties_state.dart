part of 'seller_properties_cubit.dart';

/// Loading of the seller's properties.
enum SellerPropertiesStatus { initial, loading, success, failure }

/// The properties and sale lots of the seller (EPIC-13).
final class SellerPropertiesState extends Equatable {
  const new({
    this.status = SellerPropertiesStatus.initial,
    this.properties = const [],
    this.lots = const [],
    this.parcels = const {},
  });

  final SellerPropertiesStatus status;

  /// Every property of the seller, oldest first.
  final List<Property> properties;

  /// Every sale lot of the seller, oldest first.
  final List<PropertyLot> lots;

  /// Cadastre identifiers of the parcels of the properties in a lot (by
  /// property id), for the lot estimate.
  final Map<String, Set<String>> parcels;

  /// Whether the seller may add a property (test phase limit).
  bool get canAddProperty =>
      properties.length < PropertyRepository.maxProperties;

  /// The property [id], if known.
  Property? propertyById(String id) {
    for (final property in properties) {
      if (property.id == id) return property;
    }
    return null;
  }

  /// The lot [id], if known.
  PropertyLot? lotById(String? id) {
    for (final lot in lots) {
      if (lot.id == id) return lot;
    }
    return null;
  }

  /// The properties of the lot [lotId], oldest first.
  List<Property> membersOf(String lotId) => [
    for (final property in properties)
      if (property.lotId == lotId) property,
  ];

  /// Whether the lot [lotId] is frozen: one of its properties is reviewed
  /// by the expert or certified.
  bool isLotFrozen(String? lotId) =>
      lotId != null &&
      membersOf(lotId).any(
        (p) =>
            p.status == PropertyStatus.inReview ||
            p.status == PropertyStatus.certified,
      );

  /// The properties that can join a lot: open (draft or submitted) and in
  /// no lot, oldest first.
  List<Property> get lotCandidates => [
    for (final property in standaloneProperties)
      if (property.status == PropertyStatus.draft ||
          property.status == PropertyStatus.submitted)
        property,
  ];

  /// The properties in no lot, oldest first.
  List<Property> get standaloneProperties => [
    for (final property in properties)
      if (lotById(property.lotId) == null) property,
  ];

  SellerPropertiesState copyWith({
    SellerPropertiesStatus? status,
    List<Property>? properties,
    List<PropertyLot>? lots,
    Map<String, Set<String>>? parcels,
  }) {
    return SellerPropertiesState(
      status: status ?? this.status,
      properties: properties ?? this.properties,
      lots: lots ?? this.lots,
      parcels: parcels ?? this.parcels,
    );
  }

  @override
  List<Object?> get props => [status, properties, lots, parcels];
}
