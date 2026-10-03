import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/l10n/gen/app_localizations.dart';

export 'package:realesty_backoffice/l10n/gen/app_localizations.dart';

/// Localization delegates of the back-office (French only): its strings,
/// plus the `material_ui` Material, Cupertino and widgets localizations.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
