import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/cubit/lifestyle_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/lifestyle_item_row.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/lifestyle_item_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/noise_slider.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V6 · Cadre de vie: assets and watch points of the neighbourhood, noise,
/// overlooking and a secret note. Every answer is optional.
class LifestylePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final tunnel = context.read<SellerTunnelCubit>().state;
        return LifestyleCubit(
          propertyRepository: context.read<PropertyRepository>(),
          property: tunnel.property!,
          items: tunnel.lifestyleItems,
        );
      },
      child: const LifestyleView(),
    );
  }
}

/// The V6 form, driven by [LifestyleCubit]. "Continuer" saves the items,
/// reports them to the [SellerTunnelCubit] and saves the other answers
/// (the tunnel then opens V7).
class LifestyleView extends StatefulWidget {
  const new({super.key});

  @override
  State<LifestyleView> createState() => _LifestyleViewState();
}

class _LifestyleViewState extends State<LifestyleView> {
  static const SellerTunnelStep _step = SellerTunnelStep.lifestyle;

  late final _note = TextEditingController(
    text: context.read<LifestyleCubit>().state.secretNote,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _add(LifestyleItemKind kind) async {
    final result = await showLifestyleItemSheet(context, kind: kind);
    if (result is! LifestyleItemSaved || !mounted) return;
    context.read<LifestyleCubit>().itemAdded(kind, result.label);
  }

  Future<void> _edit(LifestyleItemDraft item) async {
    final result = await showLifestyleItemSheet(
      context,
      kind: item.kind,
      initial: item.label,
    );
    if (!mounted) return;
    final cubit = context.read<LifestyleCubit>();
    switch (result) {
      case LifestyleItemSaved(:final label):
        cubit.itemEdited(item, label);
      case LifestyleItemDeleted():
        cubit.itemRemoved(item);
      case null:
        break;
    }
  }

  void _onSubmission(BuildContext context, LifestyleState state) {
    switch (state.submission) {
      case LifestyleSubmission.success:
        final tunnel = context.read<SellerTunnelCubit>()
          ..updateChildren(lifestyleItems: state.savedItems);
        unawaited(
          tunnel.saveAndContinue(_step, state.patchFor(tunnel.state.property!)),
        );
      case LifestyleSubmission.failure:
        showRealestySnackBar(
          context,
          context.l10n.sellerTunnelSaveError,
          isError: true,
        );
      case LifestyleSubmission.idle:
      case LifestyleSubmission.inProgress:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<LifestyleCubit>();
    final state = context.watch<LifestyleCubit>().state;
    final tunnelSaving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    final propertyType = context.select<SellerTunnelCubit, PropertyType?>(
      (cubit) => cubit.state.property?.propertyType,
    );
    final isBusy = state.isSubmitting || tunnelSaving;
    final noise = state.noiseLevel;
    final noiseText = noise == null
        ? l10n.lifestyleNoiseUnset
        : l10n.lifestyleNoiseValue(noise, noiseLevelLabel(l10n, noise));

    return BlocListener<LifestyleCubit, LifestyleState>(
      listenWhen: (previous, current) =>
          previous.submission != current.submission,
      listener: _onSubmission,
      child: TunnelScaffold(
        spacing: 18,
        header: TunnelHeader(
          step: _step,
          // Screen mode: the voice free talk of the mockup is deferred.
          mode: TunnelHeaderMode.screen,
          onBack: isBusy ? null : () => context.goBackFrom(_step),
        ),
        actionBar: AgentActionBar(
          hint: l10n.lifestyleHint,
          label: l10n.tunnelContinue,
          isLoading: isBusy,
          onPressed: cubit.submit,
        ),
        children: [
          AgentIntro(
            message: l10n.lifestyleIntro(switch (propertyType) {
              PropertyType.house => 'house',
              PropertyType.apartment => 'apartment',
              _ => 'other',
            }),
          ),
          for (final kind in LifestyleItemKind.values)
            _ItemsSection(
              kind: kind,
              items: state.itemsOf(kind),
              canAdd: state.canAdd(kind),
              onAdd: isBusy ? null : () => _add(kind),
              onEdit: isBusy ? null : _edit,
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                spacing: RealestySpacing.xs,
                children: [
                  Expanded(child: _FieldLabel(l10n.lifestyleNoiseLabel)),
                  // The slider announces the value.
                  ExcludeSemantics(
                    child: RealestyBadge(
                      label: noiseText,
                      variant: noiseBadgeVariant(noise),
                      showIcon: false,
                    ),
                  ),
                ],
              ),
              NoiseSlider(
                value: noise,
                onChanged: isBusy ? null : cubit.noiseLevelChanged,
                semanticLabel: l10n.lifestyleNoiseLabel,
                semanticValue: noiseText,
                minLabel: l10n.lifestyleNoiseVeryQuiet,
                maxLabel: l10n.lifestyleNoiseVeryNoisy,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              _FieldLabel(l10n.lifestyleOverlookingLabel),
              RealestySegmentedControl<Overlooking?>(
                segments: [
                  RealestySegment(
                    value: Overlooking.none,
                    label: l10n.lifestyleOverlookingNone,
                  ),
                  RealestySegment(
                    value: Overlooking.slight,
                    label: l10n.lifestyleOverlookingSlight,
                  ),
                  RealestySegment(
                    value: Overlooking.significant,
                    label: l10n.lifestyleOverlookingSignificant,
                  ),
                ],
                selected: state.overlooking,
                onChanged: isBusy
                    ? null
                    : (value) => cubit.overlookingChanged(value!),
              ),
            ],
          ),
          const _NeighbourhoodCard(),
          RealestyTextField(
            label: l10n.lifestyleSecretNoteLabel,
            hint: l10n.lifestyleSecretNoteHint,
            controller: _note,
            enabled: !isBusy,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            inputFormatters: const [CharLengthFormatter(secretNoteMaxLength)],
            onChanged: cubit.secretNoteChanged,
            footer: Text(
              '${charLength(state.secretNote)}/$secretNoteMaxLength',
              textAlign: TextAlign.end,
              style: RealestyTextStyles.badge.copyWith(
                fontWeight: FontWeight.w400,
                color: context.realestyColors.texteDiscret,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The label of noise [level] (1–10): 1–2 "Très calme", 3–4 "Calme", 5–6
/// "Modéré", 7–8 "Bruyant", 9–10 "Très bruyant".
String noiseLevelLabel(AppLocalizations l10n, int level) => switch (level) {
  <= 2 => l10n.lifestyleNoiseVeryQuiet,
  <= 4 => l10n.lifestyleNoiseQuiet,
  <= 6 => l10n.lifestyleNoiseModerate,
  <= 8 => l10n.lifestyleNoiseNoisy,
  _ => l10n.lifestyleNoiseVeryNoisy,
};

/// Badge colors of noise [level]: neutral when unanswered, green up to 4,
/// warning up to 6, error above.
RealestyBadgeVariant noiseBadgeVariant(int? level) => switch (level) {
  null => RealestyBadgeVariant.neutral,
  <= 4 => RealestyBadgeVariant.certified,
  <= 6 => RealestyBadgeVariant.toComplete,
  _ => RealestyBadgeVariant.missing,
};

/// "Atouts" or "Points de vigilance": title with count badge, the rows and
/// the add button (replaced by a note once the list is full).
class _ItemsSection extends StatelessWidget {
  const new({
    required this.kind,
    required this.items,
    required this.canAdd,
    required this.onAdd,
    required this.onEdit,
  });

  final LifestyleItemKind kind;
  final List<LifestyleItemDraft> items;
  final bool canAdd;
  final VoidCallback? onAdd;
  final ValueChanged<LifestyleItemDraft>? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAsset = kind == LifestyleItemKind.asset;
    final onEdit = this.onEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.xs,
      children: [
        SectionTitle(
          isAsset ? l10n.lifestyleAssetsTitle : l10n.lifestyleWatchPointsTitle,
          trailing: items.isEmpty
              ? null
              : Semantics(
                  label: isAsset
                      ? l10n.lifestyleAssetsCount(items.length)
                      : l10n.lifestyleWatchPointsCount(items.length),
                  excludeSemantics: true,
                  child: RealestyBadge(
                    label: frenchNumber(items.length),
                    variant: isAsset
                        ? RealestyBadgeVariant.certified
                        : RealestyBadgeVariant.toComplete,
                    showIcon: false,
                  ),
                ),
        ),
        for (final item in items)
          LifestyleItemRow(
            key: ValueKey(item.id),
            item: item,
            onEdit: onEdit == null ? null : () => onEdit(item),
          ),
        if (canAdd)
          RealestyButton(
            label: isAsset
                ? l10n.lifestyleAddAsset
                : l10n.lifestyleAddWatchPoint,
            variant: RealestyButtonVariant.text,
            leadingIcon: RealestyIcons.plus,
            height: 40,
            onPressed: onAdd,
          )
        else
          Text(
            l10n.lifestyleItemsMax(lifestyleItemsMax),
            textAlign: TextAlign.center,
            style: RealestyTextStyles.badge.copyWith(
              fontWeight: FontWeight.w400,
              color: context.realestyColors.texteDiscret,
            ),
          ),
      ],
    );
  }
}

/// Form label (13/600 Encre 2), as above the text fields.
class _FieldLabel extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: RealestyTextStyles.label.copyWith(
        color: context.realestyColors.encre2,
      ),
    );
  }
}

/// "Données du quartier": no neighbourhood data source in v1, so the card
/// only announces the external sources to come (the mockup's "Données du
/// quartier ajoutées" would be untrue).
class _NeighbourhoodCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: RealestySpacing.sm,
        children: [
          Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RealestyIcon(RealestyIcons.spark, size: 18, color: c.vertTexte),
              Text(
                l10n.lifestyleNeighbourhoodTitle,
                style: RealestyTextStyles.segment.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.encre,
                ),
              ),
              const ProvenanceTag(ProvenanceKind.externalSource),
            ],
          ),
          Text(
            l10n.lifestyleNeighbourhoodPlaceholder,
            style: RealestyTextStyles.banner.copyWith(color: c.texteDiscret),
          ),
        ],
      ),
    );
  }
}
