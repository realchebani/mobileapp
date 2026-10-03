import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The language chosen in the app, remembered on the device.
class LocalePreferences {
  const new({required this._preferences});

  final SharedPreferences _preferences;

  static const _key = 'app_locale';

  /// The chosen language code, or null for the device's language.
  String? get code {
    final code = _preferences.getString(_key);
    return LocaleCubit.supportedCodes.contains(code) ? code : null;
  }

  /// Remembers [code] (null: the device's language).
  Future<void> setCode(String? code) async {
    if (code == null) {
      await _preferences.remove(_key);
    } else {
      await _preferences.setString(_key, code);
    }
  }
}

/// The language of the app (EPIC-11, US-11.7): a code of
/// [supportedCodes], or null to follow the device. Applied at once by
/// `MaterialApp.router(locale:)` and remembered on the device; the profile
/// keeps it too (`profiles.locale`, so another device adopts it).
class LocaleCubit extends Cubit<String?> {
  new({LocalePreferences? preferences})
    : _preferences = preferences,
      super(preferences?.code);

  /// Languages of the app, French first (the reference).
  static const supportedCodes = ['fr', 'en', 'es'];

  final LocalePreferences? _preferences;

  /// Uses and remembers [code] (null: the device's language).
  Future<void> select(String? code) async {
    final value = supportedCodes.contains(code) ? code : null;
    emit(value);
    await _preferences?.setCode(value);
  }
}
