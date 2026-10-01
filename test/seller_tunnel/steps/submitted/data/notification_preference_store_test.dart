import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/data/notification_preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group(NotificationPreferenceStore, () {
    test('reads null when nothing is saved', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await NotificationPreferenceStore().read('p1'), isNull);
    });

    test('writes and reads the choice per property', () async {
      SharedPreferences.setMockInitialValues({});
      final store = NotificationPreferenceStore(
        preferences: SharedPreferences.getInstance(),
      );
      await store.write('p1', enabled: false);
      expect(await store.read('p1'), isFalse);
      expect(await store.read('p2'), isNull);
    });
  });
}
