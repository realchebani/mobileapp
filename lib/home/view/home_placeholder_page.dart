import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';
import 'package:profile_repository/profile_repository.dart';

/// Temporary seller / buyer space, until the V1 tunnel exists. Offers to
/// sign out and, in the development flavor, the design system gallery.
class HomePlaceholderPage extends StatelessWidget {
  const new({required this.role, this.showDesignSystemLink = false, super.key});

  final UserRole role;
  final bool showDesignSystemLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Scaffold(
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
                Text(switch (role) {
                  UserRole.seller => l10n.homeSellerTitle,
                  UserRole.buyer => l10n.homeBuyerTitle,
                }, style: RealestyTextStyles.title1.copyWith(color: c.encre)),
                const SizedBox(height: RealestySpacing.sm),
                Text(
                  l10n.homeComingSoon,
                  style: RealestyTextStyles.body.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
                const Spacer(),
                const SizedBox(height: RealestySpacing.xxl),
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
        ),
      ),
    );
  }
}
