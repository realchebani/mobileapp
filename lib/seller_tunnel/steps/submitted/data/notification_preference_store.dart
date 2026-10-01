import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the "Me prévenir par notification" choice of V8 on the device.
///
/// v1 has no push notifications (free Apple account), so the choice is a
/// local preference until they exist; the dossier may also be locked
/// (`in_review`), which forbids writing `properties.notify_push`.
class NotificationPreferenceStore {
  new({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;

  static String _key(String propertyId) => 'submitted.notify.$propertyId';

  /// The saved choice for [propertyId], or `null` if never set.
  Future<bool?> read(String propertyId) async =>
      (await _preferences).getBool(_key(propertyId));

  /// Saves [enabled] for [propertyId].
  Future<void> write(String propertyId, {required bool enabled}) async {
    await (await _preferences).setBool(_key(propertyId), enabled);
  }
}
