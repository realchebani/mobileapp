import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/locale/locale_cubit.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:profile_repository/profile_repository.dart';

/// Name of a language of the app, in that language ("Français").
String languageName(AppLocalizations l10n, String? code) => switch (code) {
  'fr' => 'Français',
  'en' => 'English',
  'es' => 'Español',
  _ => l10n.languageDevice,
};

/// Opens the language sheet (EPIC-11, US-11.7, not designed).
Future<void> showLanguageSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<LocaleCubit>()),
          BlocProvider.value(value: context.read<ProfileCubit>()),
        ],
        child: RepositoryProvider.value(
          value: context.read<ProfileRepository>(),
          child: const LanguageSheet(),
        ),
      ),
    );

/// "Langue de l’appareil", "Français", "English", "Español": applied at
/// once, remembered on the device and in the profile (best effort).
class LanguageSheet extends StatelessWidget {
  const new({super.key});

  static Future<void> _select(BuildContext context, String? code) async {
    final profileCubit = context.read<ProfileCubit>();
    final repository = context.read<ProfileRepository>();
    final navigator = Navigator.of(context);
    await context.read<LocaleCubit>().select(code);
    navigator.pop();
    final profile = profileCubit.state.profile;
    if (profile == null || profile.locale == code) return;
    try {
      profileCubit.profileUpdated(
        await repository
            .updateLocale(profile.id, code)
            .timeout(const Duration(seconds: 15)),
      );
    } on Object {
      // Kept on the device: the profile is only a convenience.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final current = context.watch<LocaleCubit>().state;
    final options = <String?>[null, ...LocaleCubit.supportedCodes];
    final device =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final deviceLanguage = LocaleCubit.supportedCodes.contains(device)
        ? device
        : LocaleCubit.supportedCodes.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RealestySpacing.gutter,
        0,
        RealestySpacing.gutter,
        RealestySpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
            child: Semantics(
              header: true,
              child: Text(l10n.languageTitle, style: RealestyTextStyles.title2),
            ),
          ),
          for (final (index, code) in options.indexed)
            Semantics(
              selected: code == current,
              child: RealestyListItem(
                title: languageName(l10n, code),
                subtitle: code == null
                    ? l10n.languageDeviceSubtitle(
                        languageName(l10n, deviceLanguage),
                      )
                    : null,
                showDivider: index < options.length - 1,
                trailing: code == current
                    ? RealestyIcon(RealestyIcons.check, color: c.vertTexte)
                    : null,
                onTap: () => unawaited(_select(context, code)),
              ),
            ),
          const SizedBox(height: RealestySpacing.sm),
          Text(
            l10n.languageServerNote,
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          ),
        ],
      ),
    );
  }
}
