import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/ui/ui.dart';

bool _loaded = false;

/// Loads the bundled Realesty fonts, so that texts are measured as on a
/// device instead of with the square glyphs of the default test font.
///
/// Call it from `setUpAll`.
Future<void> loadRealestyFonts() async {
  if (_loaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final MapEntry(key: family, value: files)
      in RealestyFonts.files.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
  _loaded = true;
}
