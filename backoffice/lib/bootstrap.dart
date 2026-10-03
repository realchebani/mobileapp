import 'dart:developer';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/app/browser/web_browser.dart';
import 'package:realesty_ui/realesty_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Starts the back-office with `--dart-define-from-file=config/<env>.json`
/// (Supabase URL, publishable key, redirect URL: no secret key ever).
Future<void> bootstrap() async {
  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const redirectUrl = String.fromEnvironment('AUTH_REDIRECT_URL');
  assert(
    supabaseUrl != '' && supabaseKey != '' && redirectUrl != '',
    'Missing config: run with --dart-define-from-file=config/<env>.json',
  );
  // PKCE: the magic link brings ?code= back to this site, exchanged here.
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final client = Supabase.instance.client;

  runApp(
    App(
      authRepository: BackOfficeAuthRepository(auth: client.auth),
      repository: BackOfficeRepository(client: client),
      config: const BackOfficeConfig(
        authRedirectUrl: redirectUrl,
        // Set by config/development.json only.
        // ignore: avoid_redundant_argument_values
        devPasswordLogin: bool.fromEnvironment('DEV_PASSWORD_LOGIN'),
      ),
      browser: WebBrowser(),
    ),
  );
}
