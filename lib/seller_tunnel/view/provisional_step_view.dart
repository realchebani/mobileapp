import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';

/// Placeholder of a step screen not built yet: header, agent message and
/// "Continuer" (which saves the resume point and opens the next screen).
///
/// Each `steps/<step>/<step>_page.dart` starts with it and replaces it with
/// the real screen.
class ProvisionalStepView extends StatelessWidget {
  const new({required this.step, super.key});

  final SellerTunnelStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (step == SellerTunnelStep.submitted) {
      return TunnelScaffold(
        actionBar: AgentActionBar(
          label: l10n.tunnelBackToHome,
          onPressed: context.leaveTunnel,
        ),
        children: [
          const SizedBox(height: RealestySpacing.xxl),
          Text(
            l10n.tunnelSubmittedTitle,
            textAlign: TextAlign.center,
            style: RealestyTextStyles.title1.copyWith(
              color: context.realestyColors.encre,
            ),
          ),
          AgentIntro(message: l10n.tunnelProvisionalMessage),
        ],
      );
    }
    final isSaving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    return TunnelScaffold(
      header: TunnelHeader(step: step, onBack: () => context.goBackFrom(step)),
      actionBar: AgentActionBar(
        hint: l10n.tunnelHintVoiceOrScreen,
        label: l10n.tunnelContinue,
        isLoading: isSaving,
        onPressed: () =>
            context.read<SellerTunnelCubit>().saveAndContinue(step),
      ),
      children: [AgentIntro(message: l10n.tunnelProvisionalMessage)],
    );
  }
}
