import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/dashboard/widgets/lot_card.dart';
import 'package:mobileapp/seller_space/lot/lot_member_sheet.dart';
import 'package:mobileapp/seller_space/lot/models/lot_estimate.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_card.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Fiche du lot (`/vendeur/lots/<id>`, EPIC-13): its properties (open,
/// main property, remove, add), its name, its sale mode, its estimate (sum
/// of the estimates of its properties) and "Dissoudre le lot". Frozen (read
/// only) once an expert reviews one of its properties.
class LotPage extends StatefulWidget {
  const new({required this.lotId, super.key});

  final String lotId;

  @override
  State<LotPage> createState() => _LotPageState();
}

class _LotPageState extends State<LotPage> {
  late final TextEditingController _name;
  final FocusNode _nameFocus = FocusNode();

  /// Longest lot name (`property_lots.name` check).
  static const maxNameLength = 80;

  bool _busy = false;
  bool _confirmingDissolve = false;

  @override
  void initState() {
    super.initState();
    final lot = context.read<SellerPropertiesCubit>().state.lotById(
      widget.lotId,
    );
    _name = TextEditingController(text: lot?.name);
    // Saved when the field is left, not only with "OK".
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _saveCurrentName();
    });
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  void _saveCurrentName() {
    if (!mounted) return;
    final lot = context.read<SellerPropertiesCubit>().state.lotById(
      widget.lotId,
    );
    if (lot != null) unawaited(_saveName(lot));
  }

  /// Runs [change], disabling the page meanwhile; tells the user when it
  /// failed.
  Future<void> _run(Future<void> Function(SellerPropertiesCubit) change) async {
    final l10n = context.l10n;
    final cubit = context.read<SellerPropertiesCubit>();
    setState(() => _busy = true);
    try {
      await change(cubit);
    } on LotFrozenFailure {
      if (mounted) showRealestySnackBar(context, l10n.lotFrozen, isError: true);
    } on Object {
      if (mounted) {
        showRealestySnackBar(context, l10n.lotSaveError, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The name last sent (the list may not be updated yet).
  String? _sentName;

  Future<void> _saveName(PropertyLot lot) async {
    final name = _name.text.trim();
    if (name == (_sentName ?? lot.name ?? '')) return;
    _sentName = name;
    await _run(
      (cubit) => cubit.updateLot(lot.id, {
        PropertyLotColumns.name: name.isEmpty ? null : name,
      }),
    );
  }

  Future<void> _dissolve() async {
    final router = GoRouter.of(context);
    await _run((cubit) async {
      await cubit.deleteLot(widget.lotId);
      router.go(AppRoutes.seller);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SellerPropertiesCubit>().state;
    final lot = state.lotById(widget.lotId);
    final header = Row(
      spacing: RealestySpacing.xs,
      children: [
        RealestyIconButton(
          icon: RealestyIcons.chevronLeft,
          semanticLabel: l10n.lotBack,
          onPressed: () {
            _saveCurrentName();
            context.go(AppRoutes.seller);
          },
        ),
        Expanded(child: SellerSpaceTitle(l10n.lotTitle)),
      ],
    );
    final List<Widget> children;
    if (lot == null) {
      children = [header, InlineBanner(message: l10n.lotNotFound)];
    } else {
      final members = state.membersOf(lot.id);
      final frozen = members.any(
        (p) =>
            p.status == PropertyStatus.inReview ||
            p.status == PropertyStatus.certified,
      );
      final editable = !frozen && !_busy;
      final estimate = LotEstimate.of(
        members: members,
        parcels: state.parcels,
        mainPropertyId: lot.mainPropertyId,
      );
      final candidates = state.lotCandidates;
      children = [
        header,
        if (frozen) InlineBanner(message: l10n.lotFrozen),
        RealestyTextField(
          label: l10n.lotNameLabel,
          hint: lotName(l10n, lot, members.length),
          controller: _name,
          focusNode: _nameFocus,
          enabled: editable,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(maxNameLength)],
          onSubmitted: (_) => _saveName(lot),
        ),
        SectionLabel(l10n.lotMembersLabel),
        SellerSpaceCard(
          padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, member) in members.indexed)
                _MemberRow(
                  property: member,
                  isMain: member.id == lot.mainPropertyId,
                  editable: editable,
                  showDivider: index < members.length - 1,
                  onSetMain: () => _run(
                    (cubit) => cubit.updateLot(lot.id, {
                      PropertyLotColumns.mainPropertyId: member.id,
                    }),
                  ),
                  onRemove: () => _run((cubit) => cubit.setLot(member, null)),
                ),
            ],
          ),
        ),
        if (!frozen && candidates.isNotEmpty)
          RealestyButton(
            label: l10n.lotAddMember,
            variant: RealestyButtonVariant.secondary,
            leadingIcon: RealestyIcons.plus,
            onPressed: _busy
                ? null
                : () async {
                    final chosen = await showLotMemberSheet(
                      context,
                      candidates: candidates,
                    );
                    if (chosen != null) {
                      await _run((cubit) => cubit.setLot(chosen, lot.id));
                    }
                  },
          ),
        SectionLabel(l10n.lotSaleModeLabel),
        // Chips (not a segmented control): the labels wrap when needed.
        Wrap(
          spacing: RealestySpacing.xs,
          runSpacing: RealestySpacing.xs,
          children: [
            for (final mode in LotSaleMode.values)
              RealestyChoiceChip(
                label: lotSaleModeLabel(l10n, mode),
                selected: lot.saleMode == mode,
                onSelected: editable && lot.saleMode != mode
                    ? (_) => _run(
                        (cubit) => cubit.updateLot(lot.id, {
                          PropertyLotColumns.saleMode: mode,
                        }),
                      )
                    : null,
              ),
          ],
        ),
        Text(
          l10n.lotSaleModeHelp,
          style: RealestyTextStyles.listSubtitle.copyWith(
            color: c.texteDiscret,
          ),
        ),
        SectionLabel(l10n.lotEstimateLabel),
        _EstimateCard(members: members, estimate: estimate),
        // EPIC-08: the sale of the lot.
        LotSaleCard(lot: lot),
        if (!frozen) ...[
          if (_confirmingDissolve) ...[
            InlineBanner(
              message: l10n.lotDissolveMessage,
              icon: RealestyIcons.warning,
            ),
            Row(
              spacing: RealestySpacing.xs,
              children: [
                Expanded(
                  child: RealestyButton(
                    label: l10n.myPropertiesDeleteCancel,
                    variant: RealestyButtonVariant.secondary,
                    height: 44,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _confirmingDissolve = false),
                  ),
                ),
                Expanded(
                  child: RealestyButton(
                    label: l10n.lotDissolve,
                    height: 44,
                    isLoading: _busy,
                    onPressed: _dissolve,
                  ),
                ),
              ],
            ),
          ] else
            RealestyButton(
              label: l10n.lotDissolve,
              variant: RealestyButtonVariant.text,
              onPressed: _busy
                  ? null
                  : () => setState(() => _confirmingDissolve = true),
            ),
        ],
      ];
    }
    return ColoredBox(
      color: c.ivoire,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.md,
            RealestySpacing.gutter,
            RealestySpacing.xl,
          ),
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) const SizedBox(height: RealestySpacing.sm),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const new({
    required this.property,
    required this.isMain,
    required this.editable,
    required this.showDivider,
    required this.onSetMain,
    required this.onRemove,
  });

  final Property property;
  final bool isMain;
  final bool editable;
  final bool showDivider;
  final VoidCallback onSetMain;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RealestyListItem(
          title: propertyShortLabel(l10n, property),
          subtitle: propertyStatusLabel(l10n, property),
          leadingIcon: propertyTypeIcon(property.propertyType),
          showDivider: showDivider && !editable,
          onTap: () => context.go(AppRoutes.sellerProperty(property.id)),
          trailing: isMain
              ? RealestyBadge(
                  label: l10n.lotMainBadge,
                  variant: RealestyBadgeVariant.certified,
                  showIcon: false,
                )
              : null,
        ),
        if (editable)
          Wrap(
            spacing: RealestySpacing.xs,
            children: [
              if (!isMain)
                RealestyButton(
                  label: l10n.lotSetMain,
                  variant: RealestyButtonVariant.text,
                  height: RealestySpacing.minTouchTarget,
                  expand: false,
                  onPressed: onSetMain,
                ),
              RealestyButton(
                label: l10n.lotRemoveMember,
                variant: RealestyButtonVariant.text,
                height: RealestySpacing.minTouchTarget,
                expand: false,
                onPressed: onRemove,
              ),
            ],
          ),
        if (editable && showDivider)
          Divider(height: 1, color: context.realestyColors.ligne),
      ],
    );
  }
}

/// The lot estimate: the sum once complete, and how each property counts.
class _EstimateCard extends StatelessWidget {
  const new({required this.members, required this.estimate});

  final List<Property> members;
  final LotEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return SellerSpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          if (estimate.isComplete) ...[
            Text(
              estimate.isPartial
                  ? l10n.lotEstimatePartial(
                      euros(l10n, estimate.low!),
                      euros(l10n, estimate.high!),
                    )
                  : '${euros(l10n, estimate.low!)} – '
                        '${euros(l10n, estimate.high!)}',
              style: RealestyTextStyles.title2.copyWith(color: c.encre),
            ),
            Text(
              estimate.isPartial
                  ? l10n.lotEstimatePartialNote(
                      [
                        for (final member in members)
                          if (estimate.leftOut.contains(member.id))
                            propertyShortLabel(l10n, member),
                      ].join(', '),
                    )
                  : l10n.lotEstimateSum,
              style: RealestyTextStyles.listSubtitle.copyWith(
                color: c.texteDiscret,
              ),
            ),
          ] else
            Text(
              l10n.lotEstimatePending,
              style: RealestyTextStyles.body.copyWith(color: c.texteDiscret),
            ),
          for (final (index, member) in members.indexed)
            KeyValueRow(
              label: propertyShortLabel(l10n, member),
              value: switch (estimate.members[member.id]) {
                LotMemberEstimate.included =>
                  '${euros(l10n, member.aiEstimateLowEur!)} – '
                      '${euros(l10n, member.aiEstimateHighEur!)}',
                LotMemberEstimate.includedInMain => l10n.lotEstimateIncluded,
                LotMemberEstimate.waiting => l10n.lotEstimateWaiting,
                LotMemberEstimate.notEstimated => l10n.lotEstimateNotEstimated,
                LotMemberEstimate.byExpert || null => l10n.lotEstimateByExpert,
              },
              divider: index < members.length - 1,
            ),
        ],
      ),
    );
  }
}
