import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/cubit/login_cubit.dart';
import 'package:mobileapp/ui/ui.dart';

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

/// Failure helpers shared by the login screens.
extension LoginStateFailure on LoginState {
  /// Whether opening a magic link failed.
  bool get isLinkFailure =>
      status == LoginStatus.failure &&
      (failureReason == LoginFailureReason.linkExpired ||
          failureReason == LoginFailureReason.linkInvalid);

  /// Whether this state reports a failure that [previous] did not (a new
  /// failure, or another reason while already failed).
  bool hasNewFailureSince(LoginState previous) =>
      status == LoginStatus.failure &&
      (previous.status != LoginStatus.failure ||
          previous.failureReason != failureReason);
}

/// Shows the failure of [state] in an error snackbar.
void showLoginFailure(BuildContext context, LoginState state) {
  showRealestySnackBar(
    context,
    (state.failureReason ?? LoginFailureReason.unknown).message(context.l10n),
    isError: true,
  );
}
