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
///
/// EPIC-16: [pendingSink] keeps what is said for other steps; the intro
/// lists the values pre-filled « À confirmer » ([prefilledLabels]); the
/// header's « Écrire plutôt » closes the sheet and remembers the written
/// mode. Opened by itself ([autoOpened]), a refused consent remembers the
/// written mode too.
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
  VoicePendingSink? pendingSink,
  List<String> prefilledLabels = const [],
  bool autoOpened = false,
}) async {
  final services = VoiceServices.of(context);
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!await ensureVoiceConsent(context)) {
    if (autoOpened) {
      await services.preferences?.setInputMode(VoiceInputMode.text);
    }
    return;
  }
  if (!context.mounted) return;
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
          intro: prefilledLabels.isEmpty
              ? intro
              : l10n.voiceFirstPrefilledIntro(prefilledLabels.join(', ')),
          form: form,
          pendingSink: pendingSink,
          updateLabel: (item) => prefillUpdateLabel(l10n, item),
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
            prefilledConfirmed: l10n.voiceFirstPrefilledConfirmed,
            notePrefix: l10n.prefillNotePrefix,
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
      // At most 85 % of the screen: the form stays visible behind, and the
      // actions stay pinned under the scrolling exchange.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    RealestySpacing.gutter,
                    RealestySpacing.md,
                    RealestySpacing.gutter,
                    RealestySpacing.xs,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: RealestyTextStyles.title2.copyWith(
                                  color: c.nuitTexte,
                                ),
                              ),
                            ),
                          ),
                          // EPIC-16: back to the form, remembered.
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                RealestySpacing.minTouchTarget,
                                RealestySpacing.minTouchTarget,
                              ),
                            ),
                            onPressed: () {
                              unawaited(
                                VoiceServices.of(context).preferences
                                    ?.setInputMode(VoiceInputMode.text),
                              );
                              Navigator.of(context).maybePop();
                            },
                            child: Text(
                              l10n.voiceFirstWriteInstead,
                              style: link,
                            ),
                          ),
                        ],
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
                      Semantics(
                        liveRegion: true,
                        child: AgentBubble(
                          message: lastAgent.text,
                          onDark: true,
                        ),
                      ),
                      for (final item in state.confirmations)
                        ConfirmationCard(
                          key: ValueKey(
                            '${item.turnId}/${item.confirmation.id}',
                          ),
                          label: item.confirmation.label,
                          onYes: () => unawaited(cubit.confirm(item)),
                          onNo: () => unawaited(cubit.reject(item)),
                        ),
                      if (state.applied.isNotEmpty ||
                          state.pending.isNotEmpty ||
                          state.outOfStep.isNotEmpty ||
                          state.crossStep.isNotEmpty)
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
                            for (final pill in state.crossStep)
                              CrossStepPill(
                                label: prefillNotedLabel(l10n, pill.item),
                                undoLabel: l10n.voiceSheetUndoPill(
                                  pill.item.label,
                                ),
                                onUndo: () => cubit.undoCross(pill),
                              ),
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
                      // Nothing understood for several turns.
                      if (state.suggestScreenMode)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: Text(
                              l10n.voiceFirstContinueInWriting,
                              style: link,
                            ),
                          ),
                        ),
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
                                    child: Text(
                                      l10n.voiceOpenSettings,
                                      style: link,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.gutter,
                  RealestySpacing.xs,
                  RealestySpacing.gutter,
                  RealestySpacing.md,
                ),
                child: Row(
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
              ),
            ],
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
    // The pill is drawn 28 high; its cross keeps a 44 × 44 touch target.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.lueur,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12),
            RealestyIcon(RealestyIcons.check, size: 12, color: c.encre),
            const SizedBox(width: 5),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  label,
                  style: RealestyTextStyles.badge.copyWith(color: c.encre),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: undoLabel,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUndo,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: RealestyIcon(
                      RealestyIcons.close,
                      size: 14,
                      color: c.encre,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
    // Grows with a long label (wraps) instead of overflowing.
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: c.nuitBordure),
        borderRadius: BorderRadius.circular(13),
      ),
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

/// The French name of [step] (« Noté pour Technique »).
String voiceStepLabel(AppLocalizations l10n, AgentStep step) => switch (step) {
  AgentStep.location => l10n.voiceStepLocation,
  AgentStep.context => l10n.voiceStepContext,
  AgentStep.technical => l10n.voiceStepTechnical,
  AgentStep.rooms => l10n.voiceStepRooms,
  AgentStep.lifestyle => l10n.voiceStepLifestyle,
};

/// « Noté pour Technique · Construction 1998 » (« ? » when unsure).
String prefillNotedLabel(AppLocalizations l10n, AgentCrossStep item) {
  final label = l10n.prefillNotedFor(
    voiceStepLabel(l10n, item.targetStep),
    item.label,
  );
  return item.unsure ? '$label\u00a0?' : label;
}

/// « Mettre à jour Contexte · Prix d’achat : 300 000 € → 320 000 € ? »,
/// or « Ajouter à Contexte · … ? » when the field was empty.
String prefillUpdateLabel(AppLocalizations l10n, AgentCrossStep item) {
  final step = voiceStepLabel(l10n, item.targetStep);
  final changed = item.changedLabel;
  return changed == null
      ? l10n.prefillAddTo(step, item.label)
      : l10n.prefillUpdate(step, changed);
}

/// A value said for another step (atténuée, arrow): « Noté pour Technique ·
/// Construction 1998 », with its "Annuler" cross while the sheet is open.
class CrossStepPill extends StatelessWidget {
  const new({
    required this.label,
    required this.undoLabel,
    required this.onUndo,
    super.key,
  });

  final String label;
  final String undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.lueur.withValues(alpha: 0.18),
          border: Border.all(color: c.lueur.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12),
            RealestyIcon(RealestyIcons.chevronRight, size: 12, color: c.lueur),
            const SizedBox(width: 5),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  label,
                  style: RealestyTextStyles.badge.copyWith(color: c.nuitTexte),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: undoLabel,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUndo,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: RealestyIcon(
                      RealestyIcons.close,
                      size: 14,
                      color: c.nuitTexte,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « À confirmer »: a value said on another step and pre-filled here; a
/// touch shows the words it comes from ([quote]).
class ToConfirmTag extends StatelessWidget {
  const new({this.quote, super.key});

  final String? quote;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.attentionFond,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          RealestyIcon(RealestyIcons.mic, size: 10, color: c.attention),
          // Wraps in a narrow column (rooms table) instead of overflowing.
          Flexible(
            child: Text(
              context.l10n.prefillToConfirm,
              style: RealestyTextStyles.badge.copyWith(
                color: c.attention,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
    final quote = this.quote;
    if (quote == null || quote.isEmpty) return tag;
    return Tooltip(
      message: '« $quote »',
      triggerMode: TooltipTriggerMode.tap,
      child: tag,
    );
  }
}
