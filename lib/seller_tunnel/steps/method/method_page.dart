import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/method/widgets/method_card.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/surfaces_page.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V5 · Choix de la méthode de relevé: how the rooms are measured.
///
/// v1: "Saisir manuellement" (listed first) saves `measurement_method` and
/// opens V5c; "Dicter mes pièces" (EPIC-14, when voice is available) saves
/// the same method and opens V5c with the dictation; the camera scan and
/// the plan import are shown as coming soon.
class MethodPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const MethodView();
}

class MethodView extends StatelessWidget {
  const new({super.key});

  static const SellerTunnelStep _step = SellerTunnelStep.method;

  /// "Passer cette étape": saves the rooms step (V5 and V5c) as done and
  /// opens the next step of the type.
  static Future<void> _skip(BuildContext context) async {
    final tunnel = context.read<SellerTunnelCubit>();
    await tunnel.saveAndContinue(SellerTunnelStep.surfaces);
    final next = tunnel.state.nextStep;
    if (next != null && context.mounted) context.goToTunnelStep(next);
  }

  /// "Dicter mes pièces": saves the method (`manual`, owner decision Q8)
  /// and opens V5c with the dictation (`?dictee=1`).
  static Future<void> _dictate(BuildContext context) async {
    final tunnel = context.read<SellerTunnelCubit>();
    final property = tunnel.state.property!;
    await tunnel.save({
      PropertyColumns.measurementMethod: MeasurementMethod.manual,
      if (property.currentStep < SellerTunnelStep.surfaces.number)
        PropertyColumns.currentStep: SellerTunnelStep.surfaces.number,
    });
    if (tunnel.state.saveStatus != SellerTunnelSaveStatus.success ||
        !context.mounted) {
      return;
    }
    context.go(
      '${SellerTunnelStep.surfaces.routeFor(property.id)}'
      '?${SurfacesPage.dictationQuery}=1',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final dictation =
        context.select<SellerTunnelCubit, bool>(
          (cubit) => cubit.state.profile.hasVoice(SellerTunnelStep.surfaces),
        ) &&
        VoiceServices.of(context).isAvailable;
    final saving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    final soon = RealestyBadge(label: l10n.methodSoonBadge, showIcon: false);
    final optional = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.profile.roomsOptional,
    );
    return TunnelScaffold(
      spacing: 14,
      header: TunnelHeader(
        step: _step,
        onBack: () => context.goBackFrom(_step),
      ),
      children: [
        AgentIntro(message: l10n.methodAgentMessage),
        MethodCard(
          icon: RealestyIcons.pen,
          title: l10n.methodManualTitle,
          description: l10n.methodManualDescription,
          highlighted: true,
          isLoading: saving,
          onTap: saving
              ? null
              : () => unawaited(
                  context.read<SellerTunnelCubit>().saveAndContinue(_step, {
                    PropertyColumns.measurementMethod: MeasurementMethod.manual,
                  }),
                ),
        ),
        if (dictation)
          MethodCard(
            icon: RealestyIcons.mic,
            title: l10n.methodVoiceTitle,
            description: l10n.methodVoiceDescription,
            onTap: saving ? null : () => unawaited(_dictate(context)),
          ),
        MethodCard(
          icon: RealestyIcons.scan,
          title: l10n.methodScanTitle,
          description: l10n.methodScanDescription,
          badge: soon,
          onTap: null,
        ),
        MethodCard(
          icon: RealestyIcons.plan,
          title: l10n.methodPlanTitle,
          description: l10n.methodPlanDescription,
          badge: soon,
          onTap: null,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(RealestyRadius.field),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: RealestySpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                RealestyIcon(
                  RealestyIcons.infoCircle,
                  size: 18,
                  color: c.encre2,
                ),
                Expanded(
                  child: Text(
                    l10n.methodNote,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      height: 1.45,
                      color: c.encre,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // "Autre" (péniche, moulin…): the rooms are optional.
        if (optional)
          RealestyButton(
            label: l10n.methodSkip,
            variant: RealestyButtonVariant.text,
            isLoading: saving,
            onPressed: () => unawaited(_skip(context)),
          ),
      ],
    );
  }
}
