import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/gen/app_localizations.dart';

export 'package:mobileapp/l10n/gen/app_localizations.dart';

/// Localization delegates of the app: its strings, plus the Material,
/// Cupertino and widgets localizations of `material_ui` (the generated
/// [AppLocalizations.localizationsDelegates] target `flutter/material`
/// instead, whose localizations `material_ui` widgets cannot read).
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
