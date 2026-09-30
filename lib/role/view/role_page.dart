import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:profile_repository/profile_repository.dart';

/// 02 · Sélecteur de rôle. Choosing a role saves it in the profile; the
/// router then opens the matching space.
class RolePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProfileCubit, ProfileState>(
      listenWhen: (previous, current) =>
          previous.roleUpdateStatus != current.roleUpdateStatus &&
          current.roleUpdateStatus == RoleUpdateStatus.failure,
      listener: (context, state) => showRealestySnackBar(
        context,
        context.l10n.roleSaveError,
        isError: true,
      ),
      child: const RoleView(),
    );
  }
}

class RoleView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<ProfileCubit>().state;
    final firstName = state.profile?.firstName?.trim() ?? '';
    final saving = state.roleUpdateStatus == RoleUpdateStatus.inProgress;
    void select(UserRole role) => context.read<ProfileCubit>().selectRole(role);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.xl,
            RealestySpacing.gutter,
            RealestySpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.md,
            children: [
              AgentBubble(
                senderName: l10n.agentName,
                message: firstName.isEmpty
                    ? l10n.roleGreeting
                    : l10n.roleGreetingNamed(firstName),
              ),
              RoleCard(
                dark: true,
                icon: RealestyIcons.home,
                title: l10n.roleSellerTitle,
                subtitle: l10n.roleSellerSubtitle,
                features: [l10n.roleSellerFeature1, l10n.roleSellerFeature2],
                onPressed: saving ? null : () => select(UserRole.seller),
              ),
              RoleCard(
                icon: RealestyIcons.search,
                title: l10n.roleBuyerTitle,
                subtitle: l10n.roleBuyerSubtitle,
                features: [l10n.roleBuyerFeature1, l10n.roleBuyerFeature2],
                onPressed: saving ? null : () => select(UserRole.buyer),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  RealestyIcon(
                    RealestyIcons.swap,
                    size: 18,
                    color: c.texteDiscret,
                  ),
                  Expanded(
                    child: Text(
                      l10n.roleSwitchHint,
                      style: RealestyTextStyles.label.copyWith(
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                        color: c.texteDiscret,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A role choice card: dark for the seller, light for the buyer.
class RoleCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.onPressed,
    this.dark = false,
    super.key,
  });

  final RealestyIcons icon;
  final String title;
  final String subtitle;
  final List<String> features;
  final VoidCallback? onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final foreground = dark ? c.surface : c.encre;
    final accent = dark ? c.lueur : c.vertTexte;
    return RealestyPressable(
      semanticLabel: '$title. $subtitle',
      onPressed: onPressed,
      showDisabled: false,
      child: Container(
        padding: const EdgeInsets.all(RealestySpacing.lg),
        decoration: BoxDecoration(
          color: dark ? c.encre : c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.bubble),
          border: Border.all(color: dark ? c.encre : c.bordureCarte),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark ? c.nuit3 : c.vertTeinte,
                    borderRadius: BorderRadius.circular(RealestyRadius.button),
                  ),
                  child: RealestyIcon(icon, size: 26, color: accent),
                ),
                RealestyIcon(
                  RealestyIcons.chevronRight,
                  size: 22,
                  color: foreground,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RealestySpacing.xxs,
              children: [
                Text(
                  title,
                  style: RealestyTextStyles.title2.copyWith(
                    fontSize: 22,
                    height: 1.3,
                    color: foreground,
                  ),
                ),
                Text(
                  subtitle,
                  style: RealestyTextStyles.bodySmall.copyWith(
                    color: dark ? c.nuitTexteDiscret : c.texteDiscret,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                for (final feature in features)
                  Row(
                    spacing: RealestySpacing.xs,
                    children: [
                      RealestyIcon(
                        RealestyIcons.check,
                        size: 16,
                        color: accent,
                      ),
                      Expanded(
                        child: Text(
                          feature,
                          style: RealestyTextStyles.label.copyWith(
                            fontWeight: FontWeight.w400,
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
