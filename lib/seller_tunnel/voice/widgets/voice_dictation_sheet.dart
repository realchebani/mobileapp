import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/cubit/voice_conversation_cubit.dart';
import 'package:mobileapp/seller_tunnel/voice/cubit/voice_dictation_cubit.dart';
import 'package:mobileapp/seller_tunnel/voice/view/voice_consent_page.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:mobileapp/seller_tunnel/voice/widgets/voice_widgets.dart';
import 'package:mobileapp/ui/ui.dart';

/// A plain dictation (transcription only, EPIC-14 Q2): the text said, or
/// null when the sheet is closed first. Asks the consent on first use.
Future<String?> showVoiceDictationSheet(
  BuildContext context, {
  required String propertyId,
  required AgentStep step,
  required String title,
  required String hint,
}) async {
  final services = VoiceServices.of(context);
  if (!await ensureVoiceConsent(context) || !context.mounted) return null;
  return await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.realestyColors.nuit,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => BlocProvider(
      create: (_) {
        final cubit = VoiceDictationCubit(
          agentRepository: services.agentRepository!,
          recorder: services.createRecorder!(),
          propertyId: propertyId,
          step: step,
        );
        unawaited(cubit.start());
        return cubit;
      },
      child: VoiceDictationSheet(title: title, hint: hint),
    ),
  );
}

/// The Night sheet of a dictation: orb, waveform, hint, "J’ai fini" and
/// "Annuler". Pops the text once transcribed.
class VoiceDictationSheet extends StatelessWidget {
  const new({required this.title, required this.hint, super.key});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<VoiceDictationCubit>();
    final state = context.watch<VoiceDictationCubit>().state;
    final error = state.error;
    final link = RealestyTextStyles.badge.copyWith(color: c.lueur);
    return BlocListener<VoiceDictationCubit, VoiceDictationState>(
      listenWhen: (previous, current) =>
          previous.phase != VoicePhase.done && current.phase == VoicePhase.done,
      listener: (context, state) => Navigator.of(context).pop(state.text),
      child: SafeArea(
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
                    title,
                    style: RealestyTextStyles.title2.copyWith(
                      color: c.nuitTexte,
                    ),
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
                    state.phase == VoicePhase.listening
                        ? hint
                        : voicePhaseLabel(l10n, state.phase),
                    textAlign: TextAlign.center,
                    style: RealestyTextStyles.bodySmall.copyWith(
                      color: c.nuitTexteDiscret,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (error != null) ...[
                  Text(
                    voiceErrorLabel(l10n, error),
                    style: RealestyTextStyles.bodySmall.copyWith(
                      color: c.nuitTexte,
                    ),
                  ),
                  if (error != VoiceError.quota && error != VoiceError.locked)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => unawaited(cubit.start()),
                        child: Text(l10n.voiceRetry, style: link),
                      ),
                    ),
                ],
                Row(
                  spacing: RealestySpacing.sm,
                  children: [
                    if (state.phase == VoicePhase.listening)
                      Expanded(
                        child: RealestyButton(
                          label: l10n.voiceFinishSpeaking,
                          variant: RealestyButtonVariant.accent,
                          onPressed: () => unawaited(cubit.finish()),
                        ),
                      ),
                    Expanded(
                      child: RealestyButton(
                        label: l10n.voiceDictationCancel,
                        variant: RealestyButtonVariant.secondary,
                        onPressed: () {
                          unawaited(cubit.cancel());
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
      ),
    );
  }
}
