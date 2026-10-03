import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/account/language/language_sheet.dart';
import 'package:mobileapp/seller_space/account/widgets/account_section.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/photos/photo_services.dart';
import 'package:mobileapp/seller_tunnel/photos/view/photo_consent_page.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// C2 · Mon compte ("Compte" tab, EPIC-11): identity (name of the profile,
/// else of the dossier's main owner; e-mail of the session) → V19, the
/// owners, the sign-in method, notifications, language, the vision AI
/// consent, "Mes données" (account deletion), sign out and, in the
/// development flavor, the design system. Items without an object in v1
/// (active profile, payments, invoices, Face ID, 2FA…) are hidden.
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
    final owners = context.select<SellerTunnelCubit?, String?>(
      (cubit) => _ownerNames(cubit?.state.owners ?? const []),
    );
    final unread = context.select<NotificationsCubit?, int>(
      (cubit) => cubit?.state.unreadCount ?? 0,
    );
    final language = context.select<LocaleCubit?, String?>(
      (cubit) => cubit?.state,
    );
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
                  RealestyIconButton(
                    icon: RealestyIcons.pen,
                    semanticLabel: l10n.accountEditProfile,
                    onPressed: () => context.push(AppRoutes.sellerProfile),
                  ),
                ],
              ),
            ),
            if (owners != null)
              AccountSection(
                title: l10n.accountSellerSection,
                children: [
                  RealestyListItem(
                    title: l10n.accountOwners,
                    subtitle: owners,
                    leadingIcon: RealestyIcons.users,
                    showDivider: false,
                    trailing: const _Chevron(),
                    onTap: () => context.push(AppRoutes.sellerProfile),
                  ),
                ],
              ),
            AccountSection(
              title: l10n.accountSecuritySection,
              children: [
                RealestyListItem(
                  title: l10n.accountPersonalInformation,
                  subtitle: l10n.accountPersonalInformationSubtitle,
                  leadingIcon: RealestyIcons.user,
                  trailing: const _Chevron(),
                  onTap: () => context.push(AppRoutes.sellerProfile),
                ),
                RealestyListItem(
                  title: l10n.accountSignInMethod,
                  subtitle: l10n.accountSignInMethodValue,
                  leadingIcon: RealestyIcons.mail,
                  showDivider: false,
                ),
              ],
            ),
            AccountSection(
              title: l10n.accountPreferencesSection,
              children: [
                RealestyListItem(
                  title: l10n.accountNotifications,
                  subtitle: unread > 0
                      ? l10n.accountNotificationsUnread(unread)
                      : l10n.accountNotificationsSubtitle,
                  leadingIcon: RealestyIcons.bell,
                  trailing: unread > 0
                      ? RealestyBadge(
                          label: '$unread',
                          variant: RealestyBadgeVariant.certified,
                          showIcon: false,
                        )
                      : const _Chevron(),
                  onTap: () => context.push(AppRoutes.sellerNotifications),
                ),
                RealestyListItem(
                  title: l10n.accountLanguage,
                  subtitle: languageName(l10n, language),
                  leadingIcon: RealestyIcons.chat,
                  showDivider: PhotoServices.of(context).analysisAvailable,
                  trailing: const _Chevron(),
                  onTap: () => showLanguageSheet(context),
                ),
                if (PhotoServices.of(context).analysisAvailable)
                  const _PhotoAnalysisItem(),
              ],
            ),
            AccountSection(
              title: l10n.accountPrivacySection,
              children: [
                RealestyListItem(
                  title: l10n.accountMyData,
                  subtitle: l10n.accountMyDataSubtitle,
                  leadingIcon: RealestyIcons.shield,
                  showDivider: false,
                  trailing: const _Chevron(),
                  onTap: () => context.push(AppRoutes.accountDeletion),
                ),
              ],
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

  /// "Sophie Durand, Marc Durand": the owners of the dossier, or null.
  static String? _ownerNames(List<PropertyOwner> owners) {
    final names = [
      for (final owner in owners)
        if ('${owner.firstName} ${owner.lastName}'.trim() case final name
            when name.isNotEmpty)
          name,
    ];
    return names.isEmpty ? null : names.join(', ');
  }

  /// The profile's "First Last" once its last name is known, else the
  /// main owner of the dossier, else the profile's first name.
  static String? _displayName(BuildContext context) {
    final ownerName = context.select<SellerTunnelCubit?, String?>((cubit) {
      for (final owner in cubit?.state.owners ?? const <PropertyOwner>[]) {
        if (owner.position != 1) continue;
        final name = '${owner.firstName} ${owner.lastName}'.trim();
        return name.isEmpty ? null : name;
      }
      return null;
    });
    final (
      profileName,
      hasLastName,
    ) = context.select<ProfileCubit, (String?, bool)>((cubit) {
      final profile = cubit.state.profile;
      return (profile?.fullName, profile?.lastName?.trim().isNotEmpty ?? false);
    });
    return hasLastName ? profileName : ownerName ?? profileName;
  }
}

class _Chevron extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => RealestyIcon(
    RealestyIcons.chevronRight,
    size: 18,
    color: context.realestyColors.texteDiscret,
  );
}

/// "Suggestions de l’IA sur les photos" (EPIC-15): withdraws the consent
/// to the vision AI, or asks it again.
class _PhotoAnalysisItem extends StatefulWidget {
  const new();

  @override
  State<_PhotoAnalysisItem> createState() => _PhotoAnalysisItemState();
}

class _PhotoAnalysisItemState extends State<_PhotoAnalysisItem> {
  Future<void> _toggle() async {
    final preferences = PhotoServices.of(context).preferences!;
    if (preferences.consent == PhotoAnalysisConsent.given) {
      await preferences.setConsent(given: false);
    } else {
      await ensurePhotoAnalysisConsent(context, ask: true);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final given =
        PhotoServices.of(context).preferences!.consent ==
        PhotoAnalysisConsent.given;
    return RealestyListItem(
      title: l10n.accountPhotoAnalysis,
      subtitle: given
          ? l10n.accountPhotoAnalysisOn
          : l10n.accountPhotoAnalysisOff,
      leadingIcon: RealestyIcons.camera,
      showDivider: false,
      onTap: _toggle,
    );
  }
}
