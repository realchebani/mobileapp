import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:gotrue/gotrue.dart';

/// Why sending a magic link failed.
enum SendMagicLinkFailureReason {
  /// The e-mail address was rejected by the server.
  invalidEmail,

  /// Too many e-mails were sent recently; try again later.
  rateLimited,

  /// The address may not receive e-mails (e.g. the default Supabase
  /// e-mail provider only sends to members of the project's team).
  notAuthorized,

  /// The server could not be reached or failed.
  network,

  /// Any other error.
  unknown,
}

/// {@template send_magic_link_failure}
/// Thrown when [AuthRepository.sendMagicLink] fails.
/// {@endtemplate}
class SendMagicLinkFailure implements Exception {
  /// {@macro send_magic_link_failure}
  const new(this.reason, [this.error]);

  /// Builds the failure matching an error thrown by the auth client.
  factory fromError(Object error) {
    if (error is AuthRetryableFetchException) {
      return SendMagicLinkFailure(SendMagicLinkFailureReason.network, error);
    }
    if (error is AuthException) {
      if (error.code == 'email_address_not_authorized') {
        return SendMagicLinkFailure(
          SendMagicLinkFailureReason.notAuthorized,
          error,
        );
      }
      if (error.statusCode == '429' || _rateLimitCodes.contains(error.code)) {
        return SendMagicLinkFailure(
          SendMagicLinkFailureReason.rateLimited,
          error,
        );
      }
      if (_invalidEmailCodes.contains(error.code)) {
        return SendMagicLinkFailure(
          SendMagicLinkFailureReason.invalidEmail,
          error,
        );
      }
    }
    return SendMagicLinkFailure(SendMagicLinkFailureReason.unknown, error);
  }

  static const _rateLimitCodes = {
    'over_email_send_rate_limit',
    'over_request_rate_limit',
  };

  static const _invalidEmailCodes = {
    'email_address_invalid',
    'validation_failed',
  };

  /// Why the magic link could not be sent.
  final SendMagicLinkFailureReason reason;

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'SendMagicLinkFailure($reason, $error)';
}

/// Why a magic link could not sign the user in.
enum AuthLinkFailureReason {
  /// The link expired or was already used.
  expired,

  /// The link is invalid, or was opened on another device or app install
  /// than the one that requested it (PKCE verifier missing).
  invalid,

  /// Any other error.
  unknown,
}

/// {@template auth_link_failure}
/// Emitted by [AuthRepository.linkFailures] when opening a magic link
/// failed.
/// {@endtemplate}
class AuthLinkFailure implements Exception {
  /// {@macro auth_link_failure}
  const new(this.reason, [this.error]);

  static const _expiredCodes = {'otp_expired', 'flow_state_expired'};

  static const _invalidCodes = {
    'flow_state_not_found',
    'bad_code_verifier',
    'bad_oauth_state',
    'bad_oauth_callback',
    'access_denied',
  };

  /// Classifies an error of the auth state stream, returning `null` for
  /// errors unrelated to magic links (network issues, session refresh).
  static AuthLinkFailure? tryFromError(Object error) {
    if (error is! AuthException ||
        error is AuthRetryableFetchException ||
        error is AuthSessionMissingException) {
      return null;
    }
    // Errors in the callback URL carry `error` in [AuthException.code] and
    // `error_code` in [AuthException.statusCode].
    final codes = {error.code, error.statusCode};
    if (codes.any(
      (code) =>
          code != null &&
          (code.startsWith('session_') || code.startsWith('refresh_token_')),
    )) {
      return null;
    }
    if (codes.any(_expiredCodes.contains)) {
      return AuthLinkFailure(AuthLinkFailureReason.expired, error);
    }
    if (error is AuthPKCEGrantCodeExchangeError ||
        codes.any(_invalidCodes.contains) ||
        error.message.toLowerCase().contains('code verifier')) {
      return AuthLinkFailure(AuthLinkFailureReason.invalid, error);
    }
    return AuthLinkFailure(AuthLinkFailureReason.unknown, error);
  }

  /// Why the link failed.
  final AuthLinkFailureReason reason;

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'AuthLinkFailure($reason, $error)';
}

/// {@template sign_out_failure}
/// Thrown when [AuthRepository.signOut] fails.
/// {@endtemplate}
class SignOutFailure implements Exception {
  /// {@macro sign_out_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'SignOutFailure($error)';
}

/// {@template auth_repository}
/// Manages authentication with passwordless magic links.
///
/// The auth client receives the magic link deep link itself (PKCE flow)
/// and signs the user in, which is then reported by [user].
/// {@endtemplate}
class AuthRepository {
  /// {@macro auth_repository}
  new({required this._auth, required this._redirectUrl});

  final GoTrueClient _auth;
  final String _redirectUrl;

  /// Emits the current user whenever the authentication state changes,
  /// or `null` when signed out.
  ///
  /// Stream errors (such as a failed token refresh) are dropped: the auth
  /// client reports the resulting sign-out as a regular event.
  Stream<AuthUser?> get user => _auth.onAuthStateChange
      .map((state) => state.session?.user.toAuthUser())
      .handleError((Object _) {})
      .distinct();

  /// Emits when opening a magic link fails (expired, already used,
  /// opened on another device…).
  ///
  /// The auth client replays its past events to new listeners, so a new
  /// listener may receive failures that happened before it subscribed.
  Stream<AuthLinkFailure> get linkFailures => _auth.onAuthStateChange.transform(
    StreamTransformer<AuthState, AuthLinkFailure>.fromHandlers(
      handleData: (_, _) {},
      handleError: (error, _, sink) {
        final failure = AuthLinkFailure.tryFromError(error);
        if (failure != null) sink.add(failure);
      },
    ),
  );

  /// The currently signed-in user, if any.
  AuthUser? get currentUser => _auth.currentUser?.toAuthUser();

  /// Sends a magic link to [email], creating the account if needed.
  ///
  /// Throws a [SendMagicLinkFailure] on error.
  Future<void> sendMagicLink({required String email}) async {
    try {
      await _auth.signInWithOtp(
        email: email.trim(),
        emailRedirectTo: _redirectUrl,
        shouldCreateUser: true,
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SendMagicLinkFailure.fromError(error),
        stackTrace,
      );
    }
  }

  /// Signs the current user out.
  ///
  /// Throws a [SignOutFailure] on error.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(SignOutFailure(error), stackTrace);
    }
  }
}

extension on User {
  AuthUser toAuthUser() => AuthUser(id: id, email: email);
}
