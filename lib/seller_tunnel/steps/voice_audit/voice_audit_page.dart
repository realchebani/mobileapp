import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Applies a technical turn: the validated answers are saved through the
/// tunnel cubit (same columns, RLS and lock as V4b), as "Déclaré".
VoiceTurnHandler technicalTurnHandler(SellerTunnelCubit tunnel) {
  return (turn) async {
    if (turn.patch.isEmpty || tunnel.state.property == null) return;
    // A save in progress (e.g. a previous turn) would make this one a
    // no-op: wait for it first.
    if (tunnel.state.isSaving) {
      await tunnel.stream.firstWhere((state) => !state.isSaving);
    }
    final property = tunnel.state.property!;
    await tunnel.save({
      ...turn.patch,
      PropertyColumns.provenance: property.mergeProvenance({
        for (final column in turn.patch.keys) column: Provenance.declared,
      }),
    });
    if (tunnel.state.saveStatus == SellerTunnelSaveStatus.failure) {
      throw StateError('The answers were not saved');
    }
  };
}

/// V4 · Audit vocal technique (Night): the agent asks the V4b questions
/// and fills the dossier from the seller's answers. "Passer", the keyboard
/// button and the pills open V4b (screen mode), which is always available.
class VoiceAuditPage extends StatelessWidget {
  const new({this.documentPicker, super.key});

  /// Plan import ("Importer"); the platform picker when null.
  final DocumentPicker? documentPicker;

  @override
  Widget build(BuildContext context) {
    final services = VoiceServices.of(context);
    final property = context.read<SellerTunnelCubit>().state.property!;
    // Types without voice (land, garage…): V4b asks on screen.
    final profile = context.read<SellerTunnelCubit>().state.profile;
    if (!services.isAvailable || !profile.voice) {
      return const _ScreenModeRedirect();
    }
    final intro = context.l10n.voiceAuditIntro;
    return BlocProvider(
      create: (context) {
        final tunnel = context.read<SellerTunnelCubit>();
        return VoiceConversationCubit(
          agentRepository: services.agentRepository!,
          recorder: services.createRecorder!(),
          player: services.createPlayer!(),
          preferences: services.preferences!,
          propertyId: property.id,
          step: AgentStep.technical,
          intro: intro,
          onTurn: technicalTurnHandler(tunnel),
        );
      },
      child: VoiceAuditView(
        documentPicker: documentPicker ?? PlatformDocumentPicker(),
      ),
    );
  }
}

class _ScreenModeRedirect extends StatefulWidget {
  const new();

  @override
  State<_ScreenModeRedirect> createState() => _ScreenModeRedirectState();
}

class _ScreenModeRedirectState extends State<_ScreenModeRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.goToTunnelStep(SellerTunnelStep.technical);
    });
  }

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.realestyColors.nuit);
}

/// The V4 screen, driven by [VoiceConversationCubit].
class VoiceAuditView extends StatefulWidget {
  const new({required this.documentPicker, super.key});

  final DocumentPicker documentPicker;

  @override
  State<VoiceAuditView> createState() => _VoiceAuditViewState();
}

class _VoiceAuditViewState extends State<VoiceAuditView> {
  bool _importingPlan = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    if (!mounted) return;
    final cubit = context.read<VoiceConversationCubit>();
    if (!await ensureVoiceConsent(context)) {
      if (mounted) _screenMode();
      return;
    }
    await cubit.start();
  }

  /// V4b, pre-filled with what the agent saved.
  void _screenMode() {
    unawaited(context.read<VoiceConversationCubit>().stop());
    context.goToTunnelStep(SellerTunnelStep.technical);
  }

  void _close() {
    unawaited(context.read<VoiceConversationCubit>().stop());
    context.goToTunnelStep(SellerTunnelStep.context);
  }

  Future<void> _importPlan() async {
    final l10n = context.l10n;
    final tunnel = context.read<SellerTunnelCubit>();
    final repository = context.read<PropertyRepository>();
    setState(() => _importingPlan = true);
    try {
      final file = await widget.documentPicker.pick(DocumentSource.files);
      if (file == null) return;
      final property = tunnel.state.property!;
      final document = await repository
          .uploadDocument(
            ownerId: property.ownerId,
            propertyId: property.id,
            kind: DocumentKind.plan,
            fileName: file.name,
            bytes: await file.readAsBytes(),
            mimeType: _mimeType(file.name),
          )
          .timeout(SellerTunnelCubit.defaultTimeout);
      tunnel.updateChildren(documents: [...tunnel.state.documents, document]);
      if (mounted) showRealestySnackBar(context, l10n.voiceAuditPlanImported);
    } on Object {
      if (mounted) {
        showRealestySnackBar(context, l10n.voiceAuditPlanError, isError: true);
      }
    } finally {
      if (mounted) setState(() => _importingPlan = false);
    }
  }

  static String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<VoiceConversationCubit>();
    final state = context.watch<VoiceConversationCubit>().state;
    final error = state.error;
    const step = SellerTunnelStep.technical;

    return Scaffold(
      backgroundColor: c.nuit,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.xs,
                RealestySpacing.gutter,
                RealestySpacing.xs,
              ),
              child: Row(
                children: [
                  NightRoundButton(
                    size: 44,
                    semanticLabel: l10n.voiceAuditClose,
                    onPressed: _close,
                    child: RealestyIcon(
                      RealestyIcons.close,
                      color: c.nuitTexte,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          l10n.tunnelStepCaption(step.number, step.label(l10n)),
                          style: RealestyTextStyles.badge.copyWith(
                            color: c.nuitTexteDiscret,
                          ),
                        ),
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.voiceAuditTitle,
                            style: RealestyTextStyles.title2.copyWith(
                              color: c.nuitTexte,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: c.nuit2,
                      border: Border.all(color: c.nuitBordure),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        RealestyIcon(
                          RealestyIcons.mic,
                          size: 14,
                          color: c.lueur,
                        ),
                        Text(
                          l10n.voiceAuditBadge,
                          style: RealestyTextStyles.badge.copyWith(
                            color: c.lueur,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                0,
                RealestySpacing.gutter,
                RealestySpacing.xs,
              ),
              child: Semantics(
                label: l10n.tunnelProgressLabel(
                  step.number,
                  SellerTunnelStep.count,
                ),
                child: Row(
                  spacing: 4,
                  children: [
                    for (var i = 1; i <= SellerTunnelStep.count; i++)
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= step.number ? c.lueur : c.nuitBordure,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.gutter,
                  RealestySpacing.xs,
                  RealestySpacing.gutter,
                  RealestySpacing.md,
                ),
                children: [
                  Center(
                    child: ListeningOrb(phase: state.phase, level: state.level),
                  ),
                  const SizedBox(height: 10),
                  Center(child: VoiceWaveform(levels: state.levels)),
                  const SizedBox(height: 10),
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
                        state.muted
                            ? l10n.voiceUnmuteAgent
                            : l10n.voiceMuteAgent,
                        style: RealestyTextStyles.badge.copyWith(
                          color: c.lueur,
                        ),
                      ),
                    ),
                  ),
                  if (error != null)
                    _ErrorCard(
                      message: voiceErrorLabel(l10n, error),
                      onRetry: switch (error) {
                        VoiceError.quota || VoiceError.locked => null,
                        _ => cubit.retry,
                      },
                      onSettings: error == VoiceError.permissionDenied
                          ? () => unawaited(
                              VoiceServices.of(context).openSettings(),
                            )
                          : null,
                      onScreenMode: _screenMode,
                    ),
                  if (state.suggestScreenMode)
                    _ErrorCard(
                      message: l10n.voiceSuggestScreenMode,
                      onRetry: null,
                      onSettings: null,
                      onScreenMode: _screenMode,
                    ),
                  const SizedBox(height: RealestySpacing.sm),
                  // The latest exchange only (the dossier keeps the rest).
                  for (final message in state.messages.skip(
                    state.messages.length > 2 ? state.messages.length - 2 : 0,
                  )) ...[
                    if (message.fromAgent)
                      Semantics(
                        liveRegion: true,
                        child: AgentBubble(message: message.text, onDark: true),
                      )
                    else
                      UserBubble(message: message.text, onDark: true),
                    const SizedBox(height: 10),
                  ],
                  if (state.facts.isNotEmpty || state.pending.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final fact in state.facts)
                          FactPill(label: fact.label, onPressed: _screenMode),
                        for (final pill in state.pending)
                          FactPill(
                            label: pill.label,
                            pending: true,
                            onPressed: _screenMode,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.voiceAuditFactsHint,
                      style: RealestyTextStyles.badge.copyWith(
                        color: c.nuitTexteDiscret,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _PlanCard(
                    isImporting: _importingPlan,
                    onImport: _importingPlan ? null : _importPlan,
                  ),
                ],
              ),
            ),
            if (state.phase == VoicePhase.listening)
              Center(
                child: TextButton(
                  onPressed: cubit.finishSpeaking,
                  child: Text(
                    l10n.voiceFinishSpeaking,
                    style: RealestyTextStyles.label.copyWith(color: c.lueur),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: RealestySpacing.md),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    NightRoundButton(
                      semanticLabel: l10n.voiceAuditScreenMode,
                      onPressed: _screenMode,
                      child: RealestyIcon(
                        RealestyIcons.keyboard,
                        size: 22,
                        color: c.nuitTexte,
                      ),
                    ),
                    if (state.phase == VoicePhase.done)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: RealestyButton(
                            label: l10n.voiceAuditReview,
                            onPressed: _screenMode,
                          ),
                        ),
                      )
                    else if (state.phase == VoicePhase.paused)
                      NightRoundButton(
                        size: 76,
                        accent: true,
                        semanticLabel: l10n.voiceResume,
                        onPressed: cubit.resume,
                        child: RealestyIcon(
                          RealestyIcons.mic,
                          size: 28,
                          color: c.encre,
                        ),
                      )
                    else
                      NightRoundButton(
                        size: 76,
                        accent: true,
                        semanticLabel: l10n.voicePause,
                        onPressed: cubit.pause,
                        child: PauseGlyph(color: c.encre),
                      ),
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: TextButton(
                        onPressed: _screenMode,
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text(
                          l10n.voiceAuditSkip,
                          style: RealestyTextStyles.badge.copyWith(
                            color: c.nuitTexte,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const new({
    required this.message,
    required this.onRetry,
    required this.onSettings,
    required this.onScreenMode,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;
  final VoidCallback onScreenMode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    TextButton action(String label, VoidCallback onPressed) => TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: RealestyTextStyles.badge.copyWith(color: c.lueur, fontSize: 13),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: RealestySpacing.xs),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: c.nuit2,
        border: Border.all(color: c.nuitBordure),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: RealestyTextStyles.bodySmall.copyWith(color: c.nuitTexte),
            ),
          ),
          Wrap(
            children: [
              if (onRetry case final retry?) action(l10n.voiceRetry, retry),
              if (onSettings case final settings?)
                action(l10n.voiceOpenSettings, settings),
              action(l10n.voiceAuditScreenMode, onScreenMode),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const new({required this.isImporting, required this.onImport});

  final bool isImporting;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.nuit2,
        border: Border.all(color: c.nuitBordure),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.nuit3,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: RealestyIcon(RealestyIcons.plan, color: c.lueur),
          ),
          Expanded(
            child: Text(
              l10n.voiceAuditPlanText,
              style: RealestyTextStyles.bodySmall.copyWith(
                color: c.nuitTexte,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: onImport,
              style: FilledButton.styleFrom(
                backgroundColor: c.lueur,
                foregroundColor: c.encre,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isImporting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.encre,
                        semanticsLabel: l10n.tunnelLoading,
                      ),
                    )
                  : Text(
                      l10n.voiceAuditPlanImport,
                      style: RealestyTextStyles.badge.copyWith(
                        color: c.encre,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
