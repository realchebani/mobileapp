import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Font families bundled in this package's `assets/fonts` (static TTFs from
/// Google Fonts).
///
/// Families declared by a package are registered as
/// `packages/<package>/<family>`: the constants carry that prefix, so a plain
/// `TextStyle(fontFamily: RealestyFonts.sora)` works in every app using the
/// package.
abstract final class RealestyFonts {
  /// Package that bundles the fonts and icons.
  static const package = 'realesty_ui';

  static const _prefix = 'packages/$package';

  /// Titles, prices, numbers (400–700).
  static const sora = '$_prefix/Sora';

  /// Body text and forms (400–700).
  static const hankenGrotesk = '$_prefix/HankenGrotesk';

  /// Logo wordmark only (400).
  static const michroma = '$_prefix/Michroma';

  /// OFL license files, keyed by the package names shown on the license page.
  static const licenses = <String, String>{
    'Sora': '$_prefix/assets/fonts/sora/OFL.txt',
    'Hanken Grotesk': '$_prefix/assets/fonts/hanken_grotesk/OFL.txt',
    'Michroma': '$_prefix/assets/fonts/michroma/OFL.txt',
  };

  /// Font files of each family (asset keys), for tests that load real fonts.
  static const files = <String, List<String>>{
    sora: [
      '$_prefix/assets/fonts/sora/Sora-Regular.ttf',
      '$_prefix/assets/fonts/sora/Sora-Medium.ttf',
      '$_prefix/assets/fonts/sora/Sora-SemiBold.ttf',
      '$_prefix/assets/fonts/sora/Sora-Bold.ttf',
    ],
    hankenGrotesk: [
      '$_prefix/assets/fonts/hanken_grotesk/HankenGrotesk-Regular.ttf',
      '$_prefix/assets/fonts/hanken_grotesk/HankenGrotesk-Medium.ttf',
      '$_prefix/assets/fonts/hanken_grotesk/HankenGrotesk-SemiBold.ttf',
      '$_prefix/assets/fonts/hanken_grotesk/HankenGrotesk-Bold.ttf',
    ],
    michroma: ['$_prefix/assets/fonts/michroma/Michroma-Regular.ttf'],
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
