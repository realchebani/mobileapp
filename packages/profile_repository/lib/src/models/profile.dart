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
  const new({required this.id, this.firstName, this.role});

  /// Builds a profile from a `profiles` row.
  factory fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    firstName: json['first_name'] as String?,
    role: UserRole.tryParse(json['role']),
  );

  /// Identifier of the user (same as the auth user id).
  final String id;

  /// First name, once collected.
  final String? firstName;

  /// Role, once chosen.
  final UserRole? role;

  @override
  List<Object?> get props => [id, firstName, role];
}
