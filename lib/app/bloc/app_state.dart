part of 'app_bloc.dart';

enum AppStatus {
  /// The session is still being restored.
  unknown,
  unauthenticated,
  authenticated,
}

final class AppState extends Equatable {
  const new({this.status = AppStatus.unknown, this.user});

  const new authenticated(AuthUser user)
    : this(status: AppStatus.authenticated, user: user);

  const new unauthenticated() : this(status: AppStatus.unauthenticated);

  final AppStatus status;
  final AuthUser? user;

  @override
  List<Object?> get props => [status, user];
}
