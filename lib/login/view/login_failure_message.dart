import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/cubit/login_cubit.dart';

/// User-facing message of a login failure.
extension LoginFailureMessage on LoginFailureReason {
  String message(AppLocalizations l10n) => switch (this) {
    LoginFailureReason.invalidEmail => l10n.loginFailureInvalidEmail,
    LoginFailureReason.notAuthorized => l10n.loginFailureNotAuthorized,
    LoginFailureReason.rateLimited => l10n.loginFailureRateLimited,
    LoginFailureReason.network => l10n.loginFailureNetwork,
    LoginFailureReason.linkExpired => l10n.loginFailureLinkExpired,
    LoginFailureReason.linkInvalid => l10n.loginFailureLinkInvalid,
    LoginFailureReason.unknown => l10n.loginFailureUnknown,
  };
}
