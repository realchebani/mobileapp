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
    this.pendingAnswers = const [],
    this.nextStep,
    this.continuedFrom,
    this.notFound = false,
  });

  final SellerTunnelStatus status;
  final SellerTunnelSaveStatus saveStatus;

  /// The property, once loaded.
  final Property? property;

  final List<PropertyOwner> owners;
  final List<PropertyParcel> parcels;
  final List<PreviousEstimate> previousEstimates;
  final List<Room> rooms;
  final List<LifestyleItem> lifestyleItems;
  final List<PropertyDocument> documents;

  /// Values said by voice for a step and not confirmed yet (EPIC-16).
  final List<PendingAnswer> pendingAnswers;

  /// Screen to open after a successful `saveAndContinue`; only set on that
  /// success state ([copyWith] resets it and [continuedFrom]).
  final SellerTunnelStep? nextStep;

  /// The step [nextStep] continues from (same lifetime as [nextStep]).
  final SellerTunnelStep? continuedFrom;

  /// After a failed load: the property does not exist (deleted, or not the
  /// user's).
  final bool notFound;

  /// Whether the dossier was sent: its steps can no longer be edited in
  /// the tunnel, only V8 is shown.
  ///
  /// Once submitted the database still accepts changes until the expert
  /// takes the dossier over (`lock_submitted_dossiers` migration), but the
  /// app has no "edit after sending" flow: the seller sees V8 only.
  bool get isLocked =>
      property != null && property!.status != PropertyStatus.draft;

  /// How the tunnel adapts to the type of the property.
  PropertyTypeProfile get profile =>
      PropertyTypeProfile.of(property?.propertyType);

  /// The screen where the dossier resumes (V8 once sent).
  SellerTunnelStep get resumeStep => isLocked
      ? SellerTunnelStep.submitted
      : profile.resumeAt(property?.currentStep ?? 1);

  /// Where to send the user opening the audit screen [segment] (last path
  /// segment, e.g. `technique` or `technique-vocal`) instead, or null:
  /// - V8 when the dossier [isLocked] and the screen is editable;
  /// - the next screen of this type of property when it skips that one
  ///   (e.g. the rooms of a garage).
  String? redirectFor(String segment) {
    final property = this.property;
    if (property == null) return null;
    final step = segment == SellerTunnelStep.voiceAuditSegment
        ? SellerTunnelStep.technical
        : SellerTunnelStep.fromSegment(segment);
    if (step == null || step == SellerTunnelStep.submitted) return null;
    if (isLocked) return SellerTunnelStep.submitted.routeFor(property.id);
    if (segment == SellerTunnelStep.voiceAuditSegment && !profile.voiceAudit) {
      return SellerTunnelStep.technical.routeFor(property.id);
    }
    if (!profile.includes(step)) {
      return profile.nextAfter(step).routeFor(property.id);
    }
    return null;
  }

  bool get isSaving => saveStatus == SellerTunnelSaveStatus.inProgress;

  /// Whether [step] was validated (the dossier resumes after it).
  bool isValidated(SellerTunnelStep step) {
    final property = this.property;
    return property != null &&
        profile.includes(step) &&
        step.number < property.currentStep;
  }

  /// The pending answers shown « À confirmer » on [step] (V5 and V5c share
  /// the rooms); a column this type does not ask, or whose saved value is
  /// already the one said, is hidden.
  List<PendingAnswer> pendingFor(SellerTunnelStep step) {
    final target = pendingTargetOf(step);
    if (target == null) return const [];
    return [
      for (final answer in visiblePending)
        if (answer.targetStep == target) answer,
    ];
  }

  /// Every pending answer still to confirm (V7 card).
  List<PendingAnswer> get visiblePending {
    final row = property?.toJson() ?? const <String, Object?>{};
    return [
      for (final answer in pendingAnswers)
        if (answer.kind != PendingKind.field ||
            (profile.prefills(answer.field!) &&
                !sameStoredValue(row[answer.field], answer.value)))
          answer,
    ];
  }

  /// The `pending_answers.target_step` of [step], or null (no voice).
  static String? pendingTargetOf(SellerTunnelStep step) => switch (step) {
    SellerTunnelStep.location => 'location',
    SellerTunnelStep.context => 'context',
    SellerTunnelStep.technical => 'technical',
    SellerTunnelStep.method || SellerTunnelStep.surfaces => 'rooms',
    SellerTunnelStep.lifestyle => 'lifestyle',
    SellerTunnelStep.owners ||
    SellerTunnelStep.documents ||
    SellerTunnelStep.submitted => null,
  };

  /// The tunnel screen of a pending answer's target step.
  static SellerTunnelStep stepOfTarget(String target) => switch (target) {
    'location' => SellerTunnelStep.location,
    'context' => SellerTunnelStep.context,
    'technical' => SellerTunnelStep.technical,
    'rooms' => SellerTunnelStep.surfaces,
    _ => SellerTunnelStep.lifestyle,
  };

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
    List<PendingAnswer>? pendingAnswers,
    SellerTunnelStep? nextStep,
    SellerTunnelStep? continuedFrom,
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
      pendingAnswers: pendingAnswers ?? this.pendingAnswers,
      nextStep: nextStep,
      continuedFrom: continuedFrom,
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
    pendingAnswers,
    nextStep,
    continuedFrom,
    notFound,
  ];
}
