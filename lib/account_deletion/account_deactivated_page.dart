import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';
import 'package:profile_repository/profile_repository.dart';

/// Compte désactivé — réactiver (EPIC-11): where a deactivated account
/// lands after signing in, until it is deleted for good. Reactivating
/// brings the user back to their space.
class AccountDeactivatedPage extends StatefulWidget {
  const new({super.key});

  @override
  State<AccountDeactivatedPage> createState() => _AccountDeactivatedPageState();
}

class _AccountDeactivatedPageState extends State<AccountDeactivatedPage> {
  bool _busy = false;

  Future<void> _reactivate() async {
    final l10n = context.l10n;
    final profileCubit = context.read<ProfileCubit>();
    final profile = profileCubit.state.profile;
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      await context.read<ProfileRepository>().reactivateAccount().timeout(
        const Duration(seconds: 15),
      );
      profileCubit.profileUpdated(profile.reactivated());
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      showRealestySnackBar(
        context,
        l10n.accountDeactivatedFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final due = context.select<ProfileCubit, DateTime?>(
      (cubit) => cubit.state.profile?.deletionDueAt,
    );
    return Scaffold(
      backgroundColor: c.ivoire,
      body: SafeArea(
        child: FillScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RealestySpacing.xl,
              RealestySpacing.xxxl,
              RealestySpacing.xl,
              RealestySpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RealestyLockup(),
                const SizedBox(height: 44),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.accountDeactivatedTitle,
                    style: RealestyTextStyles.title1.copyWith(color: c.encre),
                  ),
                ),
                const SizedBox(height: RealestySpacing.sm),
                Text(
                  due == null
                      ? l10n.accountDeactivatedMessageNoDate
                      : l10n.accountDeactivatedMessage(fullDate(due)),
                  style: RealestyTextStyles.body.copyWith(color: c.encre2),
                ),
                const SizedBox(height: RealestySpacing.md),
                Text(
                  l10n.accountDeactivatedHint,
                  style: RealestyTextStyles.body.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
                const Spacer(),
                const SizedBox(height: RealestySpacing.xxl),
                RealestyButton(
                  label: l10n.accountDeactivatedReactivate,
                  isLoading: _busy,
                  onPressed: _busy ? null : _reactivate,
                ),
                const SizedBox(height: RealestySpacing.sm),
                RealestyButton(
                  label: l10n.logoutButton,
                  variant: RealestyButtonVariant.secondary,
                  onPressed: _busy
                      ? null
                      : () => context.read<AppBloc>().add(
                          const AppLogoutPressed(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
