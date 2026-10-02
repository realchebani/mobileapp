part of 'owners_cubit.dart';

/// The owner 1 fields.
enum OwnerField { firstName, lastName, phone, email }

/// Progress of [OwnersCubit.submit].
enum OwnersSubmitStatus { idle, inProgress, success, failure }

/// V1 form: ownership situation, owner 1 (the user) and co-owners.
final class OwnersState extends Equatable {
  const new({
    this.ownershipType,
    this.owner = const OwnerDraft(),
    this.coOwners = const [],
    this.touched = const {},
    this.saved = const [],
    this.submitStatus = OwnersSubmitStatus.idle,
    this.showErrors = false,
    this.submitAttempts = 0,
    this.submittedOwnershipType,
    this.dictated = const {},
  });

  /// Unset until the user picks a card.
  final OwnershipType? ownershipType;

  /// Owner 1, the user (position 1).
  final OwnerDraft owner;

  /// Co-owners (positions 2, 3…), kept while "Unique propriétaire" is
  /// selected but only saved with "Plusieurs propriétaires".
  final List<OwnerDraft> coOwners;

  /// Owner 1 fields the user left once: their errors are shown.
  final Set<OwnerField> touched;

  /// The `property_owners` rows as saved in the database.
  final List<PropertyOwner> saved;

  final OwnersSubmitStatus submitStatus;

  /// Every error is shown, after "Continuer" was tapped.
  final bool showErrors;

  /// Number of "Continuer" taps with missing or invalid answers (the page
  /// then scrolls to the first error).
  final int submitAttempts;

  /// The ownership type when the last submission started: the one saved.
  final OwnershipType? submittedOwnershipType;

  /// What was answered by voice on this visit ("Dicté"): the ownership
  /// type and the dictated co-owners (`co_owner:<full name>`).
  final Set<String> dictated;

  bool get isMultiple => ownershipType == OwnershipType.multiple;

  bool get isSubmitting => submitStatus == OwnersSubmitStatus.inProgress;

  /// Whether "Continuer" is enabled: ownership chosen, owner 1 valid and,
  /// with several owners, at least one co-owner, each complete (a dictated
  /// co-owner still needs a phone number, typed on screen).
  bool get isValid =>
      ownershipType != null &&
      owner.isValid(emailRequired: true) &&
      (!isMultiple ||
          (coOwners.isNotEmpty &&
              coOwners.every((c) => c.isValid(emailRequired: false))));

  /// Whether the co-owner at [index] is still incomplete (shown after
  /// "Continuer").
  bool coOwnerIncomplete(int index) =>
      showErrors && !coOwners[index].isValid(emailRequired: false);

  /// No ownership situation chosen (shown after "Continuer").
  bool get ownershipMissing => showErrors && ownershipType == null;

  /// "Plusieurs propriétaires" without co-owner (shown after "Continuer").
  bool get coOwnersMissing => showErrors && isMultiple && coOwners.isEmpty;

  /// The error of the owner 1 [field], once it was left or after
  /// "Continuer".
  OwnerFieldError? errorOf(OwnerField field) {
    if (!showErrors && !touched.contains(field)) return null;
    return switch (field) {
      OwnerField.firstName => validateOwnerName(owner.firstName),
      OwnerField.lastName => validateOwnerName(owner.lastName),
      OwnerField.phone => validateOwnerPhone(owner.phone),
      OwnerField.email => validateOwnerEmail(owner.email, required: true),
    };
  }

  OwnersState copyWith({
    OwnershipType? ownershipType,
    OwnerDraft? owner,
    List<OwnerDraft>? coOwners,
    Set<OwnerField>? touched,
    List<PropertyOwner>? saved,
    OwnersSubmitStatus? submitStatus,
    bool? showErrors,
    int? submitAttempts,
    OwnershipType? submittedOwnershipType,
    Set<String>? dictated,
  }) {
    return OwnersState(
      ownershipType: ownershipType ?? this.ownershipType,
      owner: owner ?? this.owner,
      coOwners: coOwners ?? this.coOwners,
      touched: touched ?? this.touched,
      saved: saved ?? this.saved,
      submitStatus: submitStatus ?? this.submitStatus,
      showErrors: showErrors ?? this.showErrors,
      submitAttempts: submitAttempts ?? this.submitAttempts,
      submittedOwnershipType:
          submittedOwnershipType ?? this.submittedOwnershipType,
      dictated: dictated ?? this.dictated,
    );
  }

  @override
  List<Object?> get props => [
    ownershipType,
    owner,
    coOwners,
    touched,
    saved,
    submitStatus,
    showErrors,
    submitAttempts,
    submittedOwnershipType,
    dictated,
  ];
}
