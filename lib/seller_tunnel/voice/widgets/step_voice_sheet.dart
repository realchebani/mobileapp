import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/cubit/voice_conversation_cubit.dart';
import 'package:mobileapp/seller_tunnel/voice/view/voice_consent_page.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_form.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:mobileapp/seller_tunnel/voice/widgets/voice_widgets.dart';
import 'package:mobileapp/ui/ui.dart';

/// Opens the voice sheet of a tunnel step (EPIC-14, plan §3.1): asks the
/// consent on first use, then listens. What the agent understands goes
/// to [form] (the step's draft, nothing saved before "Continuer"); on
/// closing, a snackbar offers to undo the whole session.
///
/// [dictation] is the V5c rooms dictation: the agent stays silent
/// (a vibration per turn), listening resumes at once, and "Terminer" asks
/// the spoken summary. [extra] is shown under the exchange (the dictated
/// rooms).
Future<void> showStepVoiceSheet(
  BuildContext context, {
  required String propertyId,
  required AgentStep step,
  required VoiceForm form,
  required String title,
  required String intro,
  bool dictation = false,
  Future<AgentTurn> Function()? summary,
  Widget? extra,
  List<String> Function()? assetLabels,
  List<String> Function()? watchPointLabels,
}) async {
  final services = VoiceServices.of(context);
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!await ensureVoiceConsent(context) || !context.mounted) return;
  VoiceConversationCubit? conversation;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.realestyColors.nuit,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => BlocProvider(
      create: (_) {
        final cubit = conversation = VoiceConversationCubit(
          agentRepository: services.agentRepository!,
          recorder: services.createRecorder!(),
          player: services.createPlayer!(),
          preferences: services.preferences!,
          propertyId: propertyId,
          step: step,
          intro: intro,
          form: form,
          speakReplies: !dictation,
          stopWhenDone: !dictation,
          summary: summary,
          assetLabels: assetLabels,
          watchPointLabels: watchPointLabels,
          localReplies: VoiceLocalReplies(
            cancelled: l10n.voiceSheetCancelled,
            nothingToCancel: l10n.voiceSheetNothingToCancel,
            confirmed: l10n.voiceSheetConfirmed,
            rejected: l10n.voiceSheetRejected,
          ),
        );
        unawaited(cubit.start());
        return cubit;
      },
      child: StepVoiceSheet(title: title, dictation: dictation, extra: extra),
    ),
  );
  final session = conversation;
  if (session == null) return;
  unawaited(session.stop());
  final ids = session.state.turnIds;
  final added = session.state.applied.length;
  if (ids.isEmpty || added == 0 || messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.voiceSheetAdded(added)),
      // Goes away on its own: it must not hide "Continuer".
      persist: false,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: l10n.voiceSheetUndoSession,
        onPressed: () {
          form.undoVoiceTurnsFrom(session.state.sessionStart);
          session.reportUndone(ids);
        },
      ),
    ),
  );
}

/// The Night sheet of a step: orb, waveform, last exchange, what was
/// understood (each with its "Annuler" cross), the changes to confirm
/// (Oui / Non), "Annuler ce tour", "J’ai fini" and "Terminer".
class StepVoiceSheet extends StatelessWidget {
  const new({
    required this.title,
    this.dictation = false,
    this.extra,
    super.key,
  });

  final String title;
  final bool dictation;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<VoiceConversationCubit>();
    final state = context.watch<VoiceConversationCubit>().state;
    final error = state.error;
    final lastAgent = state.messages.lastWhere((m) => m.fromAgent);
    final lastUser = state.messages.where((m) => !m.fromAgent).lastOrNull;
    final link = RealestyTextStyles.badge.copyWith(color: c.lueur);
    return MultiBlocListener(
      listeners: [
        BlocListener<VoiceConversationCubit, VoiceConversationState>(
          listenWhen: (previous, current) =>
              !previous.finished && current.finished,
          listener: (context, state) => Navigator.of(context).maybePop(),
        ),
        // Silent dictation: a vibration for each understood room.
        BlocListener<VoiceConversationCubit, VoiceConversationState>(
          listenWhen: (previous, current) =>
              dictation && current.appliedTurns > previous.appliedTurns,
          listener: (context, state) => unawaited(HapticFeedback.lightImpact()),
        ),
      ],
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
                    size: dictation ? 64 : 95,
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
                if (!dictation)
                  Center(
                    child: TextButton(
                      onPressed: cubit.toggleMute,
                      child: Text(
                        state.muted
                            ? l10n.voiceUnmuteAgent
                            : l10n.voiceMuteAgent,
                        style: link,
                      ),
                    ),
                  ),
                if (lastUser != null)
                  UserBubble(message: lastUser.text, onDark: true),
                AgentBubble(message: lastAgent.text, onDark: true),
                for (final item in state.confirmations)
                  ConfirmationCard(
                    key: ValueKey('${item.turnId}/${item.confirmation.id}'),
                    label: item.confirmation.label,
                    onYes: () => unawaited(cubit.confirm(item)),
                    onNo: () => unawaited(cubit.reject(item)),
                  ),
                if (state.applied.isNotEmpty ||
                    state.pending.isNotEmpty ||
                    state.outOfStep.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final pill in state.applied)
                        UndoablePill(
                          label: pill.changedLabel == null
                              ? pill.label
                              : '${pill.label} · ${pill.changedLabel}',
                          undoLabel: l10n.voiceSheetUndoPill(pill.label),
                          onUndo: () => cubit.undoPill(pill),
                        ),
                      for (final pill in state.pending)
                        FactPill(label: pill.label, pending: true),
                      for (final item in state.outOfStep)
                        OutOfStepPill(label: item.label),
                    ],
                  ),
                if (state.appliedTurns > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => cubit.undoTurn(state.turnIds.last),
                      child: Text(l10n.voiceSheetUndoTurn, style: link),
                    ),
                  ),
                ?extra,
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
                              child: Text(l10n.voiceRetry, style: link),
                            ),
                          if (error == VoiceError.permissionDenied)
                            TextButton(
                              onPressed: () => unawaited(
                                VoiceServices.of(context).openSettings(),
                              ),
                              child: Text(l10n.voiceOpenSettings, style: link),
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
                        label: l10n.voiceSheetClose,
                        variant: RealestyButtonVariant.secondary,
                        onPressed: () => unawaited(cubit.finish()),
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

/// A change to confirm: its label and Oui / Non (also said aloud).
class ConfirmationCard extends StatelessWidget {
  const new({
    required this.label,
    required this.onYes,
    required this.onNo,
    super.key,
  });

  final String label;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.nuit3,
        borderRadius: BorderRadius.circular(RealestyRadius.field),
      ),
      child: Row(
        spacing: RealestySpacing.xs,
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                label,
                style: RealestyTextStyles.bodySmall.copyWith(
                  color: c.nuitTexte,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onNo,
            child: Text(
              l10n.voiceSheetNo,
              style: RealestyTextStyles.badge.copyWith(color: c.nuitTexte),
            ),
          ),
          FilledButton(
            onPressed: onYes,
            style: FilledButton.styleFrom(
              backgroundColor: c.lueur,
              foregroundColor: c.encre,
              minimumSize: const Size(56, RealestySpacing.minTouchTarget),
            ),
            child: Text(
              l10n.voiceSheetYes,
              style: RealestyTextStyles.badge.copyWith(color: c.encre),
            ),
          ),
        ],
      ),
    );
  }
}

/// An understood answer (Lueur) with its "Annuler" cross.
class UndoablePill extends StatelessWidget {
  const new({
    required this.label,
    required this.undoLabel,
    required this.onUndo,
    super.key,
  });

  final String label;

  /// Semantic label of the cross ("Annuler Construction 1998").
  final String undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: c.lueur,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          RealestyIcon(RealestyIcons.check, size: 12, color: c.encre),
          Flexible(
            child: Text(
              label,
              style: RealestyTextStyles.badge.copyWith(color: c.encre),
            ),
          ),
          Semantics(
            button: true,
            label: undoLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onUndo,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 10, 6),
                child: RealestyIcon(
                  RealestyIcons.close,
                  size: 12,
                  color: c.encre,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An answer about another step (grey): "Construction → Technique".
class OutOfStepPill extends StatelessWidget {
  const new({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.nuitBordure),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: RealestyTextStyles.badge.copyWith(color: c.nuitTexteDiscret),
      ),
    );
  }
}

/// "Dicté": a value filled by voice on this screen, until "Continuer".
class DictatedTag extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.lueur.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          RealestyIcon(RealestyIcons.mic, size: 10, color: c.encre),
          Text(
            context.l10n.voiceDictatedTag,
            style: RealestyTextStyles.badge.copyWith(
              color: c.encre,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
