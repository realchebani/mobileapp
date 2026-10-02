import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:property_repository/property_repository.dart';

/// EPIC-16 glue between a tunnel step and the voice: its [StepTraceCubit]
/// (notes, answers pre-filled « À confirmer »), its sheet opened by itself
/// when voice is the input mode, and what its « Continuer » saves besides
/// its answers.
abstract final class StepVoiceFirst {
  /// The trace of [step]: its saved note and its pending answers.
  static StepTraceCubit createTrace(
    SellerTunnelState tunnel,
    SellerTunnelStep step,
  ) => StepTraceCubit(
    StepTraceState.fromProperty(
      tunnel.property!,
      noteKey: VoiceDefaults.stepNotes
          ? SellerTunnelState.pendingTargetOf(step)
          : null,
      pending: tunnel.pendingFor(step),
    ),
  );

  /// Opens [open] after the first frame when voice is the input mode and
  /// nothing prevents it (see [VoiceFirstLauncher]).
  static void schedule(
    BuildContext context,
    SellerTunnelStep step,
    Future<void> Function() open, {
    bool when = true,
  }) {
    if (!when) return;
    final state = context.read<SellerTunnelCubit>().state;
    VoiceFirstLauncher.schedule(
      context,
      hasVoice: state.profile.hasVoice(step),
      locked: state.isLocked,
      validated: state.isValidated(step),
      hasPending: state.pendingFor(step).isNotEmpty,
      open: open,
    );
  }

  /// Whether [step] may open its sheet by itself now (a later moment of
  /// the step, e.g. V2 once the parcels are confirmed).
  static bool canAutoOpen(BuildContext context, SellerTunnelStep step) {
    final state = context.read<SellerTunnelCubit>().state;
    return VoiceFirstLauncher.skipReason(
          services: VoiceServices.of(context),
          hasVoice: state.profile.hasVoice(step),
          locked: state.isLocked,
          validated: state.isValidated(step),
          hasPending: state.pendingFor(step).isNotEmpty,
          now: DateTime.now(),
        ) ==
        null;
  }

  /// The step sheet of [step] on [form] (with its notes and the values
  /// pre-filled « À confirmer »), the tunnel keeping what is said for
  /// other steps.
  static Future<void> openSheet(
    BuildContext context, {
    required AgentStep step,
    required VoiceForm form,
    required String title,
    required String intro,
    bool autoOpened = false,
    bool dictation = false,
    Future<AgentTurn> Function()? summary,
    Widget? extra,
    List<String> Function()? assetLabels,
    List<String> Function()? watchPointLabels,
  }) {
    final tunnel = context.read<SellerTunnelCubit>();
    final trace = context.read<StepTraceCubit>();
    return showStepVoiceSheet(
      context,
      propertyId: tunnel.state.property!.id,
      step: step,
      form: TracedVoiceForm(form: form, trace: trace),
      title: title,
      intro: intro,
      dictation: dictation,
      summary: summary,
      extra: extra,
      assetLabels: assetLabels,
      watchPointLabels: watchPointLabels,
      pendingSink: tunnel,
      prefilledLabels: trace.state.toConfirmLabels,
      autoOpened: autoOpened,
    );
  }

  /// [patch] with the origin of each value, the notes, and the pending
  /// answers to resolve ([voiceSource]: `VoiceFormMixin.voiceSourceOf`).
  static StepTraceSave save(
    BuildContext context,
    Map<String, Object?> patch, {
    required FieldSource? Function(String column, Object? value, DateTime at)
    voiceSource,
    DateTime? now,
    Map<String, FieldSourceKind> kinds = const {},
  }) {
    final at = now ?? DateTime.now();
    return context.read<StepTraceCubit>().state.saveFor(
      property: context.read<SellerTunnelCubit>().state.property!,
      patch: patch,
      voiceSource: (column, value) => voiceSource(column, value, at),
      now: at,
      kinds: kinds,
    );
  }

  /// The tag of [column] holding [value] (as stored): « À confirmer » when
  /// pre-filled and not confirmed, « Dicté » when said here ([dictated])
  /// or confirmed by « oui »; null otherwise.
  static Widget? tagOf(
    BuildContext context,
    String column,
    Object? value, {
    required bool dictated,
  }) {
    final trace = context.watch<StepTraceCubit>().state;
    if (trace.toConfirm(column, value)) {
      return ToConfirmTag(quote: trace.prefilledField(column)?.quote);
    }
    if (dictated || trace.isConfirmed(column)) return const DictatedTag();
    return null;
  }
}
