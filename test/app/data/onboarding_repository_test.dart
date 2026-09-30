import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group(OnboardingRepository, () {
    test('is not seen by default', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      expect(OnboardingRepository(preferences: preferences).seen, isFalse);
    });

    test('markSeen persists the flag', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = OnboardingRepository(preferences: preferences);

      await repository.markSeen();

      expect(repository.seen, isTrue);
      expect(preferences.getBool(OnboardingRepository.seenKey), isTrue);
    });

    test('reads a stored flag', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingRepository.seenKey: true,
      });
      final preferences = await SharedPreferences.getInstance();

      expect(OnboardingRepository(preferences: preferences).seen, isTrue);
    });
  });
}
