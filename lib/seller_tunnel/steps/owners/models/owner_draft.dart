import 'package:equatable/equatable.dart';
import 'package:property_repository/property_repository.dart';

/// Why an owner field is invalid.
enum OwnerFieldError {
  /// Empty while required.
  required,

  /// Not a French phone number.
  invalidPhone,

  /// Not an e-mail address.
  invalidEmail,
}

/// Maximum length of a first or last name.
const ownerNameMaxLength = 100;

/// Validates a first or last name (required; the fields limit the length).
OwnerFieldError? validateOwnerName(String value) =>
    value.trim().isEmpty ? OwnerFieldError.required : null;

/// Validates a French mobile or landline number (required).
OwnerFieldError? validateOwnerPhone(String value) {
  if (value.trim().isEmpty) return OwnerFieldError.required;
  return phoneToE164(value) == null ? OwnerFieldError.invalidPhone : null;
}

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// Validates an e-mail address; an empty one is valid unless [required].
OwnerFieldError? validateOwnerEmail(String value, {required bool required}) {
  final email = value.trim();
  if (email.isEmpty) return required ? OwnerFieldError.required : null;
  return _email.hasMatch(email) ? null : OwnerFieldError.invalidEmail;
}

/// A French number once spaces, dots and dashes are removed:
/// `0X XX XX XX XX`, `+33 X XX XX XX XX` or `0033 X…` (X ≠ 0).
final _frenchPhone = RegExp(r'^(?:\+33|0033|0)([1-9]\d{8})$');
final _phoneSeparators = RegExp(r'[\s.\-]');

/// The E.164 form (`+33612345678`) of a French number typed as
/// `06 12 34 56 78` (or `+33 6…`), or null when it is not one.
String? phoneToE164(String value) {
  final match = _frenchPhone.firstMatch(value.replaceAll(_phoneSeparators, ''));
  return match == null ? null : '+33${match[1]}';
}

final _e164French = RegExp(r'^\+33([1-9])(\d{2})(\d{2})(\d{2})(\d{2})$');

/// How a stored phone number is shown and edited: `06 12 34 56 78` for a
/// French E.164 number, as stored otherwise.
String displayPhone(String? e164) {
  if (e164 == null) return '';
  final match = _e164French.firstMatch(e164);
  if (match == null) return e164;
  return '0${match[1]} ${match[2]} ${match[3]} ${match[4]} ${match[5]}';
}

/// An owner as edited on V1 (texts as typed); [id] is set once saved.
class OwnerDraft extends Equatable {
  const new({
    this.id,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.email = '',
  });

  /// The draft of a saved [owner].
  factory fromOwner(PropertyOwner owner) => OwnerDraft(
    id: owner.id,
    firstName: owner.firstName,
    lastName: owner.lastName,
    phone: displayPhone(owner.phone),
    email: owner.email ?? '',
  );

  final String? id;
  final String firstName;
  final String lastName;

  /// As typed, e.g. `06 12 34 56 78`.
  final String phone;
  final String email;

  /// "Marc Durand".
  String get fullName => '${firstName.trim()} ${lastName.trim()}'.trim();

  /// "MD".
  String get initials => [firstName, lastName]
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .map((name) => String.fromCharCode(name.runes.first).toUpperCase())
      .join();

  /// Whether every field is valid (the e-mail being optional unless
  /// [emailRequired]).
  bool isValid({required bool emailRequired}) =>
      validateOwnerName(firstName) == null &&
      validateOwnerName(lastName) == null &&
      validateOwnerPhone(phone) == null &&
      validateOwnerEmail(email, required: emailRequired) == null;

  /// The row of this owner at [position] of [propertyId].
  PropertyOwner toOwner({
    required String propertyId,
    required int position,
    String? profileId,
  }) {
    final email = this.email.trim();
    return PropertyOwner(
      id: id,
      propertyId: propertyId,
      position: position,
      profileId: profileId,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phone: phoneToE164(phone),
      email: email.isEmpty ? null : email,
    );
  }

  OwnerDraft copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
  }) {
    return OwnerDraft(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
    );
  }

  @override
  List<Object?> get props => [id, firstName, lastName, phone, email];
}
