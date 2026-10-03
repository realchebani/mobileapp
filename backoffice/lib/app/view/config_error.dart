import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/widgets/widgets.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Shown when the site was built without its Supabase configuration.
class ConfigErrorApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: realestyTheme(),
      locale: const Locale('fr'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: BoMessage(
            icon: RealestyIcons.warning,
            title: context.l10n.configErrorTitle,
            body: context.l10n.configErrorBody,
          ),
        ),
      ),
    );
  }
}
