import 'package:shared_preferences/shared_preferences.dart';

/// {@template onboarding_repository}
/// Remembers whether the onboarding ("Découvrir") was completed or skipped.
/// {@endtemplate}
class OnboardingRepository {
  /// {@macro onboarding_repository}
  const new({required this._preferences});

  final SharedPreferences _preferences;

  static const seenKey = 'onboarding_seen';

  /// Whether the onboarding was already seen on this device.
  bool get seen => _preferences.getBool(seenKey) ?? false;

  /// Records that the onboarding was seen.
  Future<void> markSeen() => _preferences.setBool(seenKey, true);
}
