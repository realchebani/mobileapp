/// {@template backoffice_config}
/// Settings of the back-office read from `config/<env>.json`
/// (`--dart-define-from-file`). Only the publishable key lives there.
/// {@endtemplate}
class BackOfficeConfig {
  /// {@macro backoffice_config}
  const new({required this.authRedirectUrl, this.devPasswordLogin = false});

  /// Where the magic link sends the browser back (this site).
  final String authRedirectUrl;

  /// Shows a password sign-in for test accounts (development only).
  final bool devPasswordLogin;
}
