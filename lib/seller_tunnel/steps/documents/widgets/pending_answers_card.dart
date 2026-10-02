import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V7 · « Informations dictées à confirmer (n) » (EPIC-16, Q5 a): what was
/// said by voice for a step and not confirmed there yet, each with « Voir »
/// (its step). Never blocks sending: at submission the answers still open
/// expire, unapplied (the expert sees them as « non confirmées »).
class PendingAnswersCard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final pending = context.select<SellerTunnelCubit, List<PendingAnswer>>(
      (cubit) => cubit.state.visiblePending,
    );
    if (pending.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.attentionFond,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Text(
            l10n.documentsPendingTitle(pending.length),
            style: RealestyTextStyles.label.copyWith(color: c.encre),
          ),
          Text(
            l10n.documentsPendingHint,
            style: RealestyTextStyles.listSubtitle.copyWith(color: c.encre2),
          ),
          for (final answer in pending)
            Row(
              spacing: RealestySpacing.xs,
              children: [
                Expanded(
                  child: Text(
                    '${_stepLabel(l10n, answer.targetStep)} · ${answer.label}',
                    style: RealestyTextStyles.bodySmall.copyWith(
                      color: c.encre,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      RealestySpacing.minTouchTarget,
                      RealestySpacing.minTouchTarget,
                    ),
                  ),
                  onPressed: () => context.goToTunnelStep(
                    SellerTunnelState.stepOfTarget(answer.targetStep),
                  ),
                  child: Text(
                    l10n.documentsPendingSee,
                    style: RealestyTextStyles.badge.copyWith(
                      color: c.vertTexte,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _stepLabel(AppLocalizations l10n, String target) =>
      voiceStepLabel(l10n, AgentStep.parse(target) ?? AgentStep.lifestyle);
}
