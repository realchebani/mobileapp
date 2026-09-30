import 'package:equatable/equatable.dart';

/// {@template auth_user}
/// An authenticated user, independent of the auth backend.
/// {@endtemplate}
class AuthUser extends Equatable {
  /// {@macro auth_user}
  const new({required this.id, this.email});

  /// Unique identifier of the user.
  final String id;

  /// E-mail address of the user, if any.
  final String? email;

  @override
  List<Object?> get props => [id, email];
}
