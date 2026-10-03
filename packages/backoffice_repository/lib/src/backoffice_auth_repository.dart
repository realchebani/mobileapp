import 'package:equatable/equatable.dart';
import 'package:supabase/supabase.dart';

/// Why a sign-in step failed.
enum BackOfficeAuthFailureReason { invalidCode, rateLimited, unknown }

/// {@template backoffice_auth_failure}
/// Thrown when a sign-in step fails.
/// {@endtemplate}
class BackOfficeAuthFailure implements Exception {
  /// {@macro backoffice_auth_failure}
  const new(this.reason, [this.error]);

  factory from(Object error) {
    if (error is AuthException) {
      if (error.statusCode == '429') {
        return BackOfficeAuthFailure(
          BackOfficeAuthFailureReason.rateLimited,
          error,
        );
      }
      if (error.code == 'mfa_verification_failed' ||
          error.code == 'mfa_challenge_expired' ||
          error.statusCode == '422') {
        return BackOfficeAuthFailure(
          BackOfficeAuthFailureReason.invalidCode,
          error,
        );
      }
    }
    return BackOfficeAuthFailure(BackOfficeAuthFailureReason.unknown, error);
  }

  final BackOfficeAuthFailureReason reason;
  final Object? error;

  @override
  String toString() => 'BackOfficeAuthFailure($reason, $error)';
}

/// {@template mfa_status}
/// Where the session stands with the TOTP code.
/// {@endtemplate}
class MfaStatus extends Equatable {
  /// {@macro mfa_status}
  const new({required this.passed, this.factorId});

  /// The session already passed the code (`aal2`).
  final bool passed;

  /// The verified TOTP factor; null when one must be enrolled.
  final String? factorId;

  bool get enrolled => factorId != null;

  @override
  List<Object?> get props => [passed, factorId];
}

/// {@template totp_enrollment}
/// A new TOTP factor to scan ([qrCodeSvg]) or type ([secret]).
/// {@endtemplate}
class TotpEnrollment extends Equatable {
  /// {@macro totp_enrollment}
  const new({
    required this.factorId,
    required this.qrCodeSvg,
    required this.secret,
  });

  final String factorId;
  final String qrCodeSvg;
  final String secret;

  @override
  List<Object?> get props => [factorId, qrCodeSvg, secret];
}

/// {@template backoffice_auth_repository}
/// Sign-in of the team: e-mail magic link, then a TOTP code (Supabase Auth
/// MFA). The `bo_*` functions refuse any session without `aal2`.
/// {@endtemplate}
class BackOfficeAuthRepository {
  /// {@macro backoffice_auth_repository}
  const new({required this._auth});

  final GoTrueClient _auth;

  /// Issuer shown in the authenticator app.
  static const issuer = 'Realesty Back-office';

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(BackOfficeAuthFailure.from(error), stackTrace);
    }
  }

  /// Fires on every sign-in, sign-out, token refresh and MFA step.
  Stream<AuthState> get changes => _auth.onAuthStateChange;

  bool get isSignedIn => _auth.currentSession != null;

  String? get email => _auth.currentUser?.email;

  /// Sends the magic link; the link opens [redirectTo] on this browser
  /// (PKCE).
  Future<void> sendMagicLink(String email, {required String redirectTo}) =>
      _run(
        () => _auth.signInWithOtp(
          email: email.trim(),
          emailRedirectTo: redirectTo,
        ),
      );

  /// Password sign-in (development only, test accounts).
  Future<void> signInWithPassword(String email, String password) => _run(
    () => _auth.signInWithPassword(email: email.trim(), password: password),
  );

  /// Whether the session passed the code, and the factor to challenge.
  Future<MfaStatus> mfaStatus() => _run(() async {
    final level = _auth.mfa.getAuthenticatorAssuranceLevel();
    final factors = await _auth.mfa.listFactors();
    return MfaStatus(
      passed: level.currentLevel == AuthenticatorAssuranceLevels.aal2,
      factorId: factors.totp.isEmpty ? null : factors.totp.first.id,
    );
  });

  /// Starts a TOTP enrollment (removes the unfinished ones first).
  Future<TotpEnrollment> enrollTotp() => _run(() async {
    final factors = await _auth.mfa.listFactors();
    for (final factor in factors.all) {
      if (factor.factorType == FactorType.totp &&
          factor.status != FactorStatus.verified) {
        await _auth.mfa.unenroll(factor.id);
      }
    }
    final enrollment = await _auth.mfa.enroll(
      issuer: issuer,
      friendlyName: 'Back-office ${DateTime.now().millisecondsSinceEpoch}',
    );
    final totp = enrollment.totp!;
    return TotpEnrollment(
      factorId: enrollment.id,
      qrCodeSvg: totp.qrCode,
      secret: totp.secret,
    );
  });

  /// Checks the 6-digit [code]: the session becomes `aal2`.
  Future<void> verifyTotp(String factorId, String code) => _run(
    () => _auth.mfa.challengeAndVerify(factorId: factorId, code: code.trim()),
  );

  Future<void> signOut() => _run(_auth.signOut);
}
