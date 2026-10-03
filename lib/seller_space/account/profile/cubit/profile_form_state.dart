part of 'profile_form_cubit.dart';

enum ProfileFormStatus { editing, saving, saved, failure }

/// What is wrong with a field.
enum ProfileFieldError { tooLong, invalidPhone }

final class ProfileFormState extends Equatable {
  const new({
    required this.profile,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.postalAddress = '',
    this.status = ProfileFormStatus.editing,
    this.showErrors = false,
  });

  /// The form of [profile].
  factory of(
    Profile profile, {
    ProfileFormStatus status = ProfileFormStatus.editing,
  }) => ProfileFormState(
    profile: profile,
    firstName: profile.firstName ?? '',
    lastName: profile.lastName ?? '',
    phone: profile.phone ?? '',
    postalAddress: profile.postalAddress ?? '',
    status: status,
  );

  static const maxNameLength = 100;
  static const maxAddressLength = 300;

  /// `profiles.phone` check: digits, spaces, dots, an optional leading +.
  static final phonePattern = RegExp(r'^\+?[0-9 .]{6,20}$');

  /// The saved profile.
  final Profile profile;
  final String firstName;
  final String lastName;
  final String phone;
  final String postalAddress;
  final ProfileFormStatus status;

  /// Errors are shown once "Enregistrer" was tapped with invalid values.
  final bool showErrors;

  ProfileFieldError? get firstNameError =>
      firstName.trim().length > maxNameLength
      ? ProfileFieldError.tooLong
      : null;

  ProfileFieldError? get lastNameError =>
      lastName.trim().length > maxNameLength ? ProfileFieldError.tooLong : null;

  ProfileFieldError? get phoneError {
    final value = phone.trim();
    return value.isEmpty || phonePattern.hasMatch(value)
        ? null
        : ProfileFieldError.invalidPhone;
  }

  ProfileFieldError? get postalAddressError =>
      postalAddress.trim().length > maxAddressLength
      ? ProfileFieldError.tooLong
      : null;

  bool get isValid =>
      firstNameError == null &&
      lastNameError == null &&
      phoneError == null &&
      postalAddressError == null;

  ProfileDetails get details => ProfileDetails(
    firstName: firstName,
    lastName: lastName,
    phone: phone,
    postalAddress: postalAddress,
  );

  /// Whether something was changed and not saved.
  bool get isDirty {
    final edited = details.toJson();
    final saved = ProfileDetails(
      firstName: profile.firstName,
      lastName: profile.lastName,
      phone: profile.phone,
      postalAddress: profile.postalAddress,
    ).toJson();
    return edited.keys.any((key) => edited[key] != saved[key]);
  }

  ProfileFormState copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? postalAddress,
    ProfileFormStatus? status,
    bool? showErrors,
  }) => ProfileFormState(
    profile: profile,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    phone: phone ?? this.phone,
    postalAddress: postalAddress ?? this.postalAddress,
    status: status ?? this.status,
    showErrors: showErrors ?? this.showErrors,
  );

  @override
  List<Object?> get props => [
    profile,
    firstName,
    lastName,
    phone,
    postalAddress,
    status,
    showErrors,
  ];
}
