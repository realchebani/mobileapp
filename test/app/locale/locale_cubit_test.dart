import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group(LocaleCubit, () {
    test(
      'starts from the remembered language and remembers a new one',
      () async {
        SharedPreferences.setMockInitialValues({'app_locale': 'es'});
        final preferences = LocalePreferences(
          preferences: await SharedPreferences.getInstance(),
        );
        final cubit = LocaleCubit(preferences: preferences);
        expect(cubit.state, 'es');
        await cubit.select('en');
        expect(cubit.state, 'en');
        expect(preferences.code, 'en');
        await cubit.select(null);
        expect(cubit.state, isNull);
        expect(preferences.code, isNull);
        await cubit.select('de');
        expect(cubit.state, isNull);
        await cubit.close();
      },
    );

    test('ignores an unknown remembered language', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'de'});
      final preferences = LocalePreferences(
        preferences: await SharedPreferences.getInstance(),
      );
      expect(preferences.code, isNull);
      expect(LocaleCubit().state, isNull);
      await LocaleCubit().select('fr');
    });
  });
}
