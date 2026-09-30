part of 'seller_tunnel_cubit.dart';

/// Loading of the dossier.
enum SellerTunnelStatus { initial, loading, success, failure }

/// Progress of the last save.
enum SellerTunnelSaveStatus { idle, inProgress, success, failure }

/// The seller dossier being filled: the property and its child
/// collections.
final class SellerTunnelState extends Equatable {
  const new({
    this.status = SellerTunnelStatus.initial,
    this.saveStatus = SellerTunnelSaveStatus.idle,
    this.property,
    this.owners = const [],
    this.parcels = const [],
    this.previousEstimates = const [],
    this.rooms = const [],
    this.lifestyleItems = const [],
    this.documents = const [],
    this.nextStep,
  });

  final SellerTunnelStatus status;
  final SellerTunnelSaveStatus saveStatus;

  /// The draft, once loaded.
  final Property? property;

  final List<PropertyOwner> owners;
  final List<PropertyParcel> parcels;
  final List<PreviousEstimate> previousEstimates;
  final List<Room> rooms;
  final List<LifestyleItem> lifestyleItems;
  final List<PropertyDocument> documents;

  /// Screen to open after a successful `saveAndContinue`; only set on that
  /// success state ([copyWith] resets it).
  final SellerTunnelStep? nextStep;

  /// The screen where the dossier resumes.
  SellerTunnelStep get resumeStep =>
      SellerTunnelStep.resumeAt(property?.currentStep ?? 1);

  bool get isSaving => saveStatus == SellerTunnelSaveStatus.inProgress;

  SellerTunnelState copyWith({
    SellerTunnelStatus? status,
    SellerTunnelSaveStatus? saveStatus,
    Property? property,
    List<PropertyOwner>? owners,
    List<PropertyParcel>? parcels,
    List<PreviousEstimate>? previousEstimates,
    List<Room>? rooms,
    List<LifestyleItem>? lifestyleItems,
    List<PropertyDocument>? documents,
    SellerTunnelStep? nextStep,
  }) {
    return SellerTunnelState(
      status: status ?? this.status,
      saveStatus: saveStatus ?? this.saveStatus,
      property: property ?? this.property,
      owners: owners ?? this.owners,
      parcels: parcels ?? this.parcels,
      previousEstimates: previousEstimates ?? this.previousEstimates,
      rooms: rooms ?? this.rooms,
      lifestyleItems: lifestyleItems ?? this.lifestyleItems,
      documents: documents ?? this.documents,
      nextStep: nextStep,
    );
  }

  @override
  List<Object?> get props => [
    status,
    saveStatus,
    property,
    owners,
    parcels,
    previousEstimates,
    rooms,
    lifestyleItems,
    documents,
    nextStep,
  ];
}
