import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/cubit/lifestyle_cubit.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:property_repository/property_repository.dart';

/// V6 · "Parlez librement": the step voice sheet (EPIC-14). What the agent
/// understands goes to the V6 form ([LifestyleCubit.applyVoiceTurn]);
/// nothing is saved before "Continuer".
///
/// EPIC-16: opened by itself in the voice mode ([autoOpened]), with the
/// notes and the items pre-filled « À confirmer ».
Future<void> showLifestyleVoiceSheet(
  BuildContext context, {
  bool autoOpened = false,
}) async {
  final l10n = context.l10n;
  final lifestyle = context.read<LifestyleCubit>();
  List<String> labels(LifestyleItemKind kind) => [
    for (final item in lifestyle.state.itemsOf(kind)) item.label,
  ];
  await StepVoiceFirst.openSheet(
    context,
    step: AgentStep.lifestyle,
    form: lifestyle,
    title: l10n.lifestyleVoiceTitle,
    intro: l10n.lifestyleVoiceIntro,
    assetLabels: () => labels(LifestyleItemKind.asset),
    watchPointLabels: () => labels(LifestyleItemKind.watchPoint),
    autoOpened: autoOpened,
  );
}
