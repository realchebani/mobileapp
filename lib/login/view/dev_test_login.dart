import 'package:auth_repository/auth_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// Credentials of the development test account, which signs in with a
/// password instead of a magic link (the default Supabase e-mail provider
/// is heavily rate-limited).
///
/// They are never committed: `DEV_TEST_EMAIL` and `DEV_TEST_PASSWORD` come
/// from the gitignored `config/development.local.json`, passed with an
/// extra `--dart-define-from-file`.
class DevTestCredentials {
  const new({required this.email, required this.password});

  /// The credentials of this build, or `null` when the test sign-in is
  /// unavailable.
  static final DevTestCredentials? fromEnvironment = resolve(
    flavor: appFlavor,
    email: const String.fromEnvironment('DEV_TEST_EMAIL'),
    password: const String.fromEnvironment('DEV_TEST_PASSWORD'),
  );

  /// The credentials, only in the development flavor and when both values
  /// are set.
  static DevTestCredentials? resolve({
    required String? flavor,
    required String email,
    required String password,
  }) {
    if (flavor != 'development' || email.isEmpty || password.isEmpty) {
      return null;
    }
    return DevTestCredentials(email: email, password: password);
  }

  final String email;
  final String password;
}

/// Discreet "Connexion de test (dev)" button of the login screen (01):
/// signs in with [credentials]; the app router then leaves the screen.
class DevTestLoginButton extends StatefulWidget {
  const new({required this.credentials, super.key});

  final DevTestCredentials credentials;

  @override
  State<DevTestLoginButton> createState() => _DevTestLoginButtonState();
}

class _DevTestLoginButtonState extends State<DevTestLoginButton> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      await context.read<AuthRepository>().signInWithPassword(
        email: widget.credentials.email,
        password: widget.credentials.password,
      );
    } on SignInWithPasswordFailure catch (failure) {
      if (!mounted) return;
      setState(() => _signingIn = false);
      final l10n = context.l10n;
      showRealestySnackBar(context, switch (failure.reason) {
        SignInWithPasswordFailureReason.invalidCredentials =>
          l10n.loginDevTestInvalidCredentials,
        SignInWithPasswordFailureReason.network => l10n.loginFailureNetwork,
        SignInWithPasswordFailureReason.unknown => l10n.loginFailureUnknown,
      }, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Center(
      child: TextButton(
        onPressed: _signingIn ? null : _signIn,
        style: TextButton.styleFrom(
          foregroundColor: c.texteDiscret,
          minimumSize: const Size(
            RealestySpacing.minTouchTarget,
            RealestySpacing.minTouchTarget,
          ),
          textStyle: RealestyTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        child: _signingIn
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.texteDiscret,
                ),
              )
            : Text(context.l10n.loginDevTestButton),
      ),
    );
  }
}
