import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';

/// Home of a draft property ("Mon dossier vendeur"): starts or resumes the
/// audit. Signing out and the design system link live in the "Compte" tab.
class SellerHomePage extends StatelessWidget {
  const new({this.onBack, this.footer, super.key});

  /// Back to "Mes biens" (seller with several properties).
  final VoidCallback? onBack;

  /// Shown under the button (lot of the property, "Ajouter un bien").
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final (step, profile, currentStep) = context
        .select<
          SellerTunnelCubit,
          (SellerTunnelStep, PropertyTypeProfile, int)
        >(
          (cubit) => (
            cubit.state.resumeStep,
            cubit.state.profile,
            cubit.state.property?.currentStep ?? 1,
          ),
        );
    final label = step == SellerTunnelStep.owners
        ? l10n.sellerHomeStart
        : l10n.sellerHomeResume(profile.positionOf(step), profile.stepCount);
    return Scaffold(
      backgroundColor: c.ivoire,
      body: SafeArea(
        bottom: false,
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
                if (onBack case final onBack?)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: RealestyIconButton(
                      icon: RealestyIcons.chevronLeft,
                      semanticLabel: l10n.propertyHomeBack,
                      onPressed: onBack,
                    ),
                  )
                else
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
                  total: profile.stepCount,
                  completed: profile.completedAt(currentStep),
                ),
                const Spacer(),
                const SizedBox(height: RealestySpacing.xxl),
                RealestyButton(
                  label: label,
                  onPressed: () => context.goToTunnelStep(step),
                ),
                if (footer case final footer?) ...[
                  const SizedBox(height: RealestySpacing.md),
                  footer,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
