import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/photos/view/photo_consent_page.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_option_sheets.dart';
import 'package:mobileapp/seller_tunnel/steps/method/plan/plan_reading_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/method/plan/plan_review_page.dart';
import 'package:mobileapp/seller_tunnel/steps/method/widgets/method_card.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/surfaces_page.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V5 · Choix de la méthode de relevé: how the rooms are measured.
///
/// "Saisir manuellement" (listed first) saves `measurement_method` and
/// opens V5c; "Dicter mes pièces" (EPIC-14, when voice is available) saves
/// the same method and opens V5c with the dictation; "Lire un plan"
/// (EPIC-15) reads the rooms printed on a photographed plan with the vision
/// AI, the seller checks them line by line, and they open V5c. The camera
/// scan card was removed (owner decision Q7).
class MethodPage extends StatelessWidget {
  const new({this.documentPicker, this.encodePlan, super.key});

  /// Defaults to the document scanner and the photo library of the device.
  final DocumentPicker? documentPicker;

  /// Defaults to [encodePlanImage].
  final PlanImageEncoder? encodePlan;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<DocumentPicker>(
      create: (_) => documentPicker ?? PlatformDocumentPicker(),
      child: BlocProvider(
        create: (context) => PlanReadingCubit(
          repository: context.read<PropertyRepository>(),
          property: context.read<SellerTunnelCubit>().state.property!,
          encode: encodePlan,
        ),
        child: const MethodView(),
      ),
    );
  }
}

/// Where the photo of the plan comes from.
enum PlanSource { scan, library }

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

  /// "Lire un plan": the photo of the plan (scanner or library), stored as
  /// a `plan` document; read by the vision AI with the seller's consent
  /// (otherwise only filed for the expert), checked line by line, and the
  /// rooms kept are written (`source = plan`) before V5c opens.
  static Future<void> _readPlan(BuildContext context) async {
    final l10n = context.l10n;
    final tunnel = context.read<SellerTunnelCubit>();
    final cubit = context.read<PlanReadingCubit>();
    final picker = context.read<DocumentPicker>();
    final source = await _showPlanSourceSheet(context);
    if (source == null || !context.mounted) return;
    final Uint8List? image;
    try {
      image = switch (source) {
        PlanSource.scan => await (await picker.scanPages(
          maxPages: 1,
        ))?.firstOrNull?.readAsBytes(),
        PlanSource.library => await (await picker.pick(
          DocumentSource.photos,
        ))?.readAsBytes(),
      };
    } on Object catch (error) {
      if (context.mounted) {
        showRealestySnackBar(
          context,
          error is DocumentAccessDenied
              ? l10n.methodPlanAccessDenied
              : l10n.methodPlanUploadError,
          isError: true,
        );
      }
      return;
    }
    if (image == null || !context.mounted) return;
    final consent = await ensurePhotoAnalysisConsent(context, ask: true);
    await cubit.store(image);
    final document = cubit.state.document;
    if (document == null || !context.mounted) return;
    tunnel.updateChildren(documents: [...tunnel.state.documents, document]);
    if (!consent) {
      showRealestySnackBar(context, l10n.methodPlanSavedNoAi);
      await tunnel.saveAndContinue(_step, {
        PropertyColumns.measurementMethod: MeasurementMethod.plan,
      });
      return;
    }
    await cubit.read(document);
    final reading = cubit.state.reading;
    if (reading == null || !context.mounted) return;
    final result = await showPlanReview(context, reading);
    switch (result) {
      case null:
        return;
      case PlanReviewManual():
        await tunnel.saveAndContinue(_step, {
          PropertyColumns.measurementMethod: MeasurementMethod.manual,
        });
      case PlanReviewAccepted(:final rooms):
        final existing = tunnel.state.rooms;
        await cubit.saveRooms(
          rooms,
          existing: existing,
          onSaved: (saved) => tunnel.updateChildren(
            rooms: [
              for (final room in existing)
                if (!saved.any((s) => s.id == room.id)) room,
              ...saved,
            ],
          ),
        );
        if (!cubit.state.roomsSaved) return;
        await tunnel.saveAndContinue(_step, {
          PropertyColumns.measurementMethod: MeasurementMethod.plan,
        });
    }
  }

  static Future<PlanSource?> _showPlanSourceSheet(BuildContext context) {
    final l10n = context.l10n;
    return showModalBottomSheet<PlanSource>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => DocumentOptionSheet<PlanSource>(
        title: l10n.methodPlanSheetTitle,
        options: [
          DocumentOption(
            value: PlanSource.scan,
            title: l10n.methodPlanScan,
            icon: RealestyIcons.scan,
          ),
          DocumentOption(
            value: PlanSource.library,
            title: l10n.methodPlanLibrary,
            icon: RealestyIcons.camera,
          ),
        ],
      ),
    );
  }

  static String _noticeMessage(AppLocalizations l10n, PlanReadingNotice n) =>
      switch (n) {
        PlanReadingNotice.uploadFailed => l10n.methodPlanUploadError,
        PlanReadingNotice.readFailed => l10n.methodPlanError,
        PlanReadingNotice.quota => l10n.methodPlanQuota,
        PlanReadingNotice.saveFailed => l10n.planReviewSaveError,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final dictation =
        context.select<SellerTunnelCubit, bool>(
          (cubit) => cubit.state.profile.hasVoice(SellerTunnelStep.surfaces),
        ) &&
        VoiceServices.of(context).isAvailable;
    final reading = context.watch<PlanReadingCubit>().state;
    final saving =
        context.select<SellerTunnelCubit, bool>(
          (cubit) => cubit.state.isSaving,
        ) ||
        reading.isBusy;
    final optional = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.profile.roomsOptional,
    );
    return BlocListener<PlanReadingCubit, PlanReadingState>(
      listenWhen: (previous, current) =>
          previous.noticeCount != current.noticeCount,
      listener: (context, state) => showRealestySnackBar(
        context,
        _noticeMessage(l10n, state.notice!),
        isError: true,
      ),
      child: TunnelScaffold(
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
                      PropertyColumns.measurementMethod:
                          MeasurementMethod.manual,
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
            icon: RealestyIcons.plan,
            title: l10n.methodPlanTitle,
            description: l10n.methodPlanDescription,
            isLoading: reading.isBusy,
            onTap: saving ? null : () => unawaited(_readPlan(context)),
          ),
          if (reading.status
              case PlanReadingStatus.uploading || PlanReadingStatus.reading)
            Semantics(
              liveRegion: true,
              child: Text(
                reading.status == PlanReadingStatus.uploading
                    ? l10n.methodPlanUploading
                    : l10n.methodPlanReading,
                textAlign: TextAlign.center,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  color: c.texteDiscret,
                ),
              ),
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
      ),
    );
  }
}
