import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Font families bundled in `assets/fonts` (static TTFs from Google Fonts).
abstract final class RealestyFonts {
  /// Titles, prices, numbers (400–700).
  static const sora = 'Sora';

  /// Body text and forms (400–700).
  static const hankenGrotesk = 'HankenGrotesk';

  /// Logo wordmark only (400).
  static const michroma = 'Michroma';

  /// OFL license files, keyed by the package names shown on the license page.
  static const licenses = <String, String>{
    'Sora': 'assets/fonts/sora/OFL.txt',
    'Hanken Grotesk': 'assets/fonts/hanken_grotesk/OFL.txt',
    'Michroma': 'assets/fonts/michroma/OFL.txt',
  };
}

/// Registers the SIL Open Font License of each bundled font with the
/// [LicenseRegistry], so they appear on the Flutter license page.
///
/// Call once at startup, before `runApp`.
void registerFontLicenses({AssetBundle? bundle}) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final entry in RealestyFonts.licenses.entries) {
      final license = await assets.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], license);
    }
  });
}
