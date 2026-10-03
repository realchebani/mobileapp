part of 'session_cubit.dart';

enum SessionStatus {
  /// Checking the session.
  unknown,

  /// No session: sign in with a magic link.
  signedOut,

  /// Signed in, the TOTP code is missing (enrol or verify).
  mfa,

  /// Signed in with the code, but not an active member of the team.
  denied,

  /// The back-office could not be reached.
  failed,

  /// Ready: [SessionState.me] is a member with an MFA session.
  ready,
}

class SessionState extends Equatable {
  const new({this.status = SessionStatus.unknown, this.me, this.mfa});

  final SessionStatus status;
  final StaffMe? me;
  final MfaStatus? mfa;

  @override
  List<Object?> get props => [status, me, mfa];
}
