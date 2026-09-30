import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/ui/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerFontLicenses adds the OFL of each font', () async {
    registerFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();
    expect(packages, containsAll(['Sora', 'Hanken Grotesk', 'Michroma']));
    final sora = entries.firstWhere((e) => e.packages.contains('Sora'));
    final text = sora.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL Open Font License'));
  });

  test('font assets are declared', () async {
    for (final path in RealestyFonts.licenses.values) {
      expect(await rootBundle.loadString(path), isNotEmpty);
    }
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets(),
      containsAll([
        'assets/fonts/sora/Sora-SemiBold.ttf',
        'assets/fonts/hanken_grotesk/HankenGrotesk-Regular.ttf',
        'assets/fonts/michroma/Michroma-Regular.ttf',
      ]),
    );
  });
}
