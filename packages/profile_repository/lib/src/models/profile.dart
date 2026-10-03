import 'package:equatable/equatable.dart';

/// The role a user picked in the app.
enum UserRole {
  /// Wants to sell a property.
  seller,

  /// Wants to buy a property.
  buyer;

  /// Parses a stored role, returning `null` for unknown values.
  static UserRole? tryParse(Object? value) {
    for (final role in values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

/// {@template profile}
/// Public profile of a user (row of the `profiles` table).
/// {@endtemplate}
class Profile extends Equatable {
  /// {@macro profile}
  const new({
    required this.id,
    this.firstName,
    this.role,
    this.lastName,
    this.phone,
    this.postalAddress,
    this.locale,
    this.deactivatedAt,
    this.deletionDueAt,
  });

  /// Builds a profile from a `profiles` row.
  factory fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    firstName: json['first_name'] as String?,
    role: UserRole.tryParse(json['role']),
    lastName: json['last_name'] as String?,
    phone: json['phone'] as String?,
    postalAddress: json['postal_address'] as String?,
    locale: json['locale'] as String?,
    deactivatedAt: _date(json['deactivated_at']),
    deletionDueAt: _date(json['deletion_due_at']),
  );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.parse(value) : null;

  /// Identifier of the user (same as the auth user id).
  final String id;

  /// First name, once collected.
  final String? firstName;

  /// Role, once chosen.
  final UserRole? role;

  /// Last name (V19).
  final String? lastName;

  /// Phone number (V19).
  final String? phone;

  /// Postal address, free text (V19).
  final String? postalAddress;

  /// Language chosen in the app (`fr`, `en`, `es`); null = the device's.
  final String? locale;

  /// When the user asked to delete the account (deactivated since then).
  final DateTime? deactivatedAt;

  /// When the deactivated account is deleted for good.
  final DateTime? deletionDueAt;

  /// Whether the account is deactivated (its deletion is pending).
  bool get isDeactivated => deactivatedAt != null;

  /// "First Last", or null when neither is known.
  String? get fullName {
    final name = [
      firstName?.trim() ?? '',
      lastName?.trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    return name.isEmpty ? null : name;
  }

  /// This profile with [role].
  Profile withRole(UserRole role) => _copy(role: role);

  /// This profile with the [locale] chosen in the app (null = device).
  Profile withLocale(String? locale) => _copy(locale: () => locale);

  /// This profile reactivated.
  Profile reactivated() =>
      _copy(deactivatedAt: () => null, deletionDueAt: () => null);

  Profile _copy({
    UserRole? role,
    String? Function()? locale,
    DateTime? Function()? deactivatedAt,
    DateTime? Function()? deletionDueAt,
  }) => Profile(
    id: id,
    firstName: firstName,
    role: role ?? this.role,
    lastName: lastName,
    phone: phone,
    postalAddress: postalAddress,
    locale: locale == null ? this.locale : locale(),
    deactivatedAt: deactivatedAt == null ? this.deactivatedAt : deactivatedAt(),
    deletionDueAt: deletionDueAt == null ? this.deletionDueAt : deletionDueAt(),
  );

  @override
  List<Object?> get props => [
    id,
    firstName,
    role,
    lastName,
    phone,
    postalAddress,
    locale,
    deactivatedAt,
    deletionDueAt,
  ];
}

/// {@template profile_details}
/// The personal information the user edits in V19.
/// {@endtemplate}
class ProfileDetails extends Equatable {
  /// {@macro profile_details}
  const new({this.firstName, this.lastName, this.phone, this.postalAddress});

  /// First name (empty values are stored as null, like the others).
  final String? firstName;

  /// Last name.
  final String? lastName;

  /// Phone number.
  final String? phone;

  /// Postal address, free text.
  final String? postalAddress;

  /// The columns of `profiles` to update.
  Map<String, Object?> toJson() => {
    'first_name': _value(firstName),
    'last_name': _value(lastName),
    'phone': _value(phone),
    'postal_address': _value(postalAddress),
  };

  static String? _value(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  List<Object?> get props => [firstName, lastName, phone, postalAddress];
}
