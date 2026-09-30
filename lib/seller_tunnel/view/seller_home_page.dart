import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';

/// Seller space ("Mon dossier vendeur"): starts or resumes the audit,
/// signs out and, in the development flavor, opens the design system.
class SellerHomePage extends StatelessWidget {
  const new({this.showDesignSystemLink = false, super.key});

  final bool showDesignSystemLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final step = context.select<SellerTunnelCubit, SellerTunnelStep>(
      (cubit) => cubit.state.resumeStep,
    );
    final String label;
    if (step == SellerTunnelStep.submitted) {
      label = l10n.sellerHomeSubmitted;
    } else if (step == SellerTunnelStep.owners) {
      label = l10n.sellerHomeStart;
    } else {
      label = l10n.sellerHomeResume(step.number, SellerTunnelStep.count);
    }
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
                Text(
                  l10n.sellerHomeTitle,
                  style: RealestyTextStyles.title1.copyWith(color: c.encre),
                ),
                const SizedBox(height: RealestySpacing.sm),
                Text(
                  l10n.sellerHomeSubtitle,
                  style: RealestyTextStyles.body.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
                const SizedBox(height: RealestySpacing.xl),
                SegmentedProgress(
                  total: SellerTunnelStep.count,
                  completed: step.number - 1,
                ),
                const Spacer(),
                const SizedBox(height: RealestySpacing.xxl),
                RealestyButton(
                  label: label,
                  onPressed: () => context.goToTunnelStep(step),
                ),
                const SizedBox(height: RealestySpacing.sm),
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
