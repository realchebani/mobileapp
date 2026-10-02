import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/cubit/lifestyle_cubit.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V6 · "Parlez librement": asks the consent on first use, then opens the
/// Night listening sheet. What the agent understands goes to the V6 form
/// ([LifestyleCubit.voiceTurnApplied]); nothing is saved before
/// "Continuer".
Future<void> showLifestyleVoiceSheet(BuildContext context) async {
  final services = VoiceServices.of(context);
  final lifestyle = context.read<LifestyleCubit>();
  final propertyId = context.read<SellerTunnelCubit>().state.property!.id;
  final intro = context.l10n.lifestyleVoiceIntro;
  if (!await ensureVoiceConsent(context) || !context.mounted) return;
  List<String> labels(LifestyleItemKind kind) => [
    for (final item in lifestyle.state.itemsOf(kind)) item.label,
  ];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.realestyColors.nuit,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => BlocProvider(
      create: (_) {
        final cubit = VoiceConversationCubit(
          agentRepository: services.agentRepository!,
          recorder: services.createRecorder!(),
          player: services.createPlayer!(),
          preferences: services.preferences!,
          propertyId: propertyId,
          step: AgentStep.lifestyle,
          intro: intro,
          onTurn: lifestyle.voiceTurnApplied,
          assetLabels: () => labels(LifestyleItemKind.asset),
          watchPointLabels: () => labels(LifestyleItemKind.watchPoint),
        );
        unawaited(cubit.start());
        return cubit;
      },
      child: const LifestyleVoiceSheet(),
    ),
  );
}

/// The Night sheet of V6: orb (95), waveform, last exchange, "J’ai fini"
/// and "Terminer".
class LifestyleVoiceSheet extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<VoiceConversationCubit>();
    final state = context.watch<VoiceConversationCubit>().state;
    final error = state.error;
    final lastAgent = state.messages.lastWhere((m) => m.fromAgent);
    final lastUser = state.messages.where((m) => !m.fromAgent).lastOrNull;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.md,
            RealestySpacing.gutter,
            RealestySpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.lifestyleVoiceTitle,
                  style: RealestyTextStyles.title2.copyWith(color: c.nuitTexte),
                ),
              ),
              Center(
                child: ListeningOrb(
                  phase: state.phase,
                  level: state.level,
                  size: 95,
                ),
              ),
              Center(child: VoiceWaveform(levels: state.levels)),
              Semantics(
                liveRegion: true,
                child: Text(
                  voicePhaseLabel(l10n, state.phase),
                  textAlign: TextAlign.center,
                  style: RealestyTextStyles.bodySmall.copyWith(
                    color: c.nuitTexteDiscret,
                    fontSize: 13,
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: cubit.toggleMute,
                  child: Text(
                    state.muted ? l10n.voiceUnmuteAgent : l10n.voiceMuteAgent,
                    style: RealestyTextStyles.badge.copyWith(color: c.lueur),
                  ),
                ),
              ),
              if (lastUser != null)
                UserBubble(message: lastUser.text, onDark: true),
              AgentBubble(message: lastAgent.text, onDark: true),
              if (error != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      voiceErrorLabel(l10n, error),
                      style: RealestyTextStyles.bodySmall.copyWith(
                        color: c.nuitTexte,
                      ),
                    ),
                    Wrap(
                      children: [
                        if (error != VoiceError.quota &&
                            error != VoiceError.locked)
                          TextButton(
                            onPressed: cubit.retry,
                            child: Text(
                              l10n.voiceRetry,
                              style: RealestyTextStyles.badge.copyWith(
                                color: c.lueur,
                              ),
                            ),
                          ),
                        if (error == VoiceError.permissionDenied)
                          TextButton(
                            onPressed: () => unawaited(
                              VoiceServices.of(context).openSettings(),
                            ),
                            child: Text(
                              l10n.voiceOpenSettings,
                              style: RealestyTextStyles.badge.copyWith(
                                color: c.lueur,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              Row(
                spacing: RealestySpacing.sm,
                children: [
                  if (state.phase == VoicePhase.listening)
                    Expanded(
                      child: RealestyButton(
                        label: l10n.voiceFinishSpeaking,
                        variant: RealestyButtonVariant.accent,
                        onPressed: cubit.finishSpeaking,
                      ),
                    ),
                  Expanded(
                    child: RealestyButton(
                      label: l10n.lifestyleVoiceClose,
                      variant: RealestyButtonVariant.secondary,
                      onPressed: () {
                        unawaited(cubit.stop());
                        Navigator.of(context).pop();
                      },
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
