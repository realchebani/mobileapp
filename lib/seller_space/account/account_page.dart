import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// C2 · Mon compte ("Compte" tab), v1: identity (name from the profile
/// and the dossier owner, e-mail of the session), sign-in method,
/// language, sign out and, in the development flavor, the design system.
/// Editing the profile (V19), preferences and account deletion come with
/// EPIC-11.
class AccountPage extends StatelessWidget {
  const new({this.showDesignSystemLink = false, super.key});

  final bool showDesignSystemLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final email = context.select<AppBloc, String?>(
      (bloc) => bloc.state.user?.email,
    );
    final name = _displayName(context);
    return ColoredBox(
      color: c.ivoire,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.md,
            RealestySpacing.gutter,
            RealestySpacing.xl,
          ),
          children: [
            SellerSpaceTitle(l10n.accountTitle),
            const SizedBox(height: RealestySpacing.lg),
            SellerSpaceCard(
              child: Row(
                spacing: RealestySpacing.sm,
                children: [
                  InitialsAvatar(
                    name == null ? '?' : InitialsAvatar.of(name),
                    size: 48,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          name ?? l10n.accountNoName,
                          style: RealestyTextStyles.listTitle.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.encre,
                          ),
                        ),
                        if (email != null)
                          Text(
                            email,
                            style: RealestyTextStyles.listSubtitle.copyWith(
                              color: c.texteDiscret,
                            ),
                          ),
                        const SizedBox(height: RealestySpacing.xxs),
                        RealestyBadge(
                          label: l10n.accountRoleSeller,
                          variant: RealestyBadgeVariant.essentiel,
                          showIcon: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _Section(
              title: l10n.accountSecuritySection,
              children: [
                RealestyListItem(
                  title: l10n.accountSignInMethod,
                  subtitle: l10n.accountSignInMethodValue,
                  leadingIcon: RealestyIcons.mail,
                  showDivider: false,
                ),
              ],
            ),
            _Section(
              title: l10n.accountPreferencesSection,
              children: [
                RealestyListItem(
                  title: l10n.accountLanguage,
                  subtitle: l10n.accountLanguageValue,
                  leadingIcon: RealestyIcons.chat,
                  showDivider: false,
                ),
              ],
            ),
            const SizedBox(height: RealestySpacing.md),
            InlineBanner(
              message: l10n.accountMoreSoon,
              variant: InlineBannerVariant.info,
            ),
            const SizedBox(height: RealestySpacing.xl),
            RealestyButton(
              label: l10n.logoutButton,
              variant: RealestyButtonVariant.secondary,
              onPressed: () =>
                  context.read<AppBloc>().add(const AppLogoutPressed()),
            ),
            if (showDesignSystemLink) ...[
              const SizedBox(height: RealestySpacing.sm),
              RealestyButton(
                label: l10n.homeDesignSystem,
                variant: RealestyButtonVariant.text,
                onPressed: () => context.push(AppRoutes.designSystem),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "First Last" from the main owner of the dossier, else the profile's
  /// first name.
  static String? _displayName(BuildContext context) {
    final ownerName = context.select<SellerTunnelCubit?, String?>((cubit) {
      for (final owner in cubit?.state.owners ?? const <PropertyOwner>[]) {
        if (owner.position != 1) continue;
        final name = '${owner.firstName} ${owner.lastName}'.trim();
        return name.isEmpty ? null : name;
      }
      return null;
    });
    final firstName = context.select<ProfileCubit, String?>(
      (cubit) => cubit.state.profile?.firstName?.trim(),
    );
    return ownerName ?? ((firstName?.isEmpty ?? true) ? null : firstName);
  }
}

class _Section extends StatelessWidget {
  const new({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Padding(
      padding: const EdgeInsets.only(top: RealestySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Text(
            title.toUpperCase(),
            style: RealestyTextStyles.caption.copyWith(color: c.texteDiscret),
          ),
          SellerSpaceCard(
            padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
