part of 'login_cubit.dart';

enum LoginStatus {
  /// Entering the e-mail.
  initial,

  /// A magic link is being sent.
  submitting,

  /// The magic link was sent to [LoginState.sentTo].
  sent,

  /// Sending failed, see [LoginState.failureReason].
  failure,
}

/// Why the login failed.
enum LoginFailureReason {
  /// The server rejected the e-mail address.
  invalidEmail,

  /// The address may not receive e-mails (default Supabase e-mail provider:
  /// team members only).
  notAuthorized,

  /// Too many e-mails were sent; wait before resending.
  rateLimited,

  /// The server could not be reached.
  network,

  /// The magic link expired or was already used.
  linkExpired,

  /// The magic link is invalid (or opened on another device).
  linkInvalid,

  unknown,
}

final class LoginState extends Equatable {
  const new({
    this.email = '',
    this.termsAccepted = false,
    this.status = LoginStatus.initial,
    this.failureReason,
    this.sentTo,
    this.resendAvailableIn = 0,
  });

  static final _emailRegExp = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+"
    '@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*'
    r'\.[a-zA-Z]{2,}$',
  );

  /// The e-mail as typed.
  final String email;

  /// Whether the terms of use were accepted.
  final bool termsAccepted;

  final LoginStatus status;

  /// Why sending, or signing in with the link, failed, when [status] is
  /// [LoginStatus.failure].
  final LoginFailureReason? failureReason;

  /// The address the last magic link was sent to; non-null from the first
  /// successful send until [LoginCubit.editEmail] (the "check your inbox"
  /// step, including while resending or after a failed resend).
  final String? sentTo;

  /// Seconds before the link can be resent (0 when it can).
  final int resendAvailableIn;

  bool get isEmailValid => _emailRegExp.hasMatch(email.trim());

  bool get canSubmit =>
      isEmailValid && termsAccepted && status != LoginStatus.submitting;

  bool get canResend =>
      sentTo != null &&
      resendAvailableIn == 0 &&
      status != LoginStatus.submitting;

  LoginState copyWith({
    String? email,
    bool? termsAccepted,
    LoginStatus? status,
    LoginFailureReason? Function()? failureReason,
    String? Function()? sentTo,
    int? resendAvailableIn,
  }) {
    return LoginState(
      email: email ?? this.email,
      termsAccepted: termsAccepted ?? this.termsAccepted,
      status: status ?? this.status,
      failureReason: failureReason != null
          ? failureReason()
          : this.failureReason,
      sentTo: sentTo != null ? sentTo() : this.sentTo,
      resendAvailableIn: resendAvailableIn ?? this.resendAvailableIn,
    );
  }

  @override
  List<Object?> get props => [
    email,
    termsAccepted,
    status,
    failureReason,
    sentTo,
    resendAvailableIn,
  ];
}
