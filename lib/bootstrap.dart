import 'dart:async';
import 'dart:developer';

import 'package:auth_repository/auth_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Builds the root widget from the app dependencies (e.g. `App.new`).
typedef AppBuilder = FutureOr<Widget> Function({
  required AuthRepository authRepository,
  required ProfileRepository profileRepository,
  required PropertyRepository propertyRepository,
  required GeoRepository geoRepository,
  required OnboardingRepository onboardingRepository,
});

Future<void> bootstrap(AppBuilder builder) async {
  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

  // Provided per flavor via --dart-define-from-file=config/<flavor>.json
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const authRedirectUrl = String.fromEnvironment('AUTH_REDIRECT_URL');
  assert(
    supabaseUrl != '' && supabaseKey != '',
    'Missing Supabase config: run with '
    '--dart-define-from-file=config/<flavor>.json',
  );
  assert(
    authRedirectUrl != '',
    'Missing AUTH_REDIRECT_URL: run with '
    '--dart-define-from-file=config/<flavor>.json',
  );
  // Keep the default PKCE auth flow: magic links rely on it.
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final client = Supabase.instance.client;
  final preferences = await SharedPreferences.getInstance();

  runApp(
    await builder(
      authRepository: AuthRepository(
        auth: client.auth,
        redirectUrl: authRedirectUrl,
      ),
      profileRepository: ProfileRepository(client: client),
      propertyRepository: PropertyRepository(client: client),
      geoRepository: GeoRepository(),
      onboardingRepository: OnboardingRepository(preferences: preferences),
    ),
  );
}
