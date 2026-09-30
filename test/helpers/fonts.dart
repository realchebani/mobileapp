import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

/// Loads the bundled Realesty fonts, so that texts are measured as on a
/// device instead of with the square glyphs of the default test font.
///
/// Call it from `setUpAll`.
Future<void> loadRealestyFonts() async {
  if (_loaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  const families = {
    'Sora': [
      'assets/fonts/sora/Sora-Regular.ttf',
      'assets/fonts/sora/Sora-Medium.ttf',
      'assets/fonts/sora/Sora-SemiBold.ttf',
      'assets/fonts/sora/Sora-Bold.ttf',
    ],
    'HankenGrotesk': [
      'assets/fonts/hanken_grotesk/HankenGrotesk-Regular.ttf',
      'assets/fonts/hanken_grotesk/HankenGrotesk-Medium.ttf',
      'assets/fonts/hanken_grotesk/HankenGrotesk-SemiBold.ttf',
      'assets/fonts/hanken_grotesk/HankenGrotesk-Bold.ttf',
    ],
    'Michroma': ['assets/fonts/michroma/Michroma-Regular.ttf'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
  _loaded = true;
}
