import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/new_property/cubit/new_property_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Ajouter un bien" (`/vendeur/biens/nouveau`, EPIC-13), full screen above
/// the tabs: the type (V3 grid), "Vendu avec un autre bien ?" (lot) and
/// "Reprendre mes informations" (owners and identity document copied from
/// another property). "Commencer l’audit" opens V1 of the new property.
class NewPropertyPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => NewPropertyCubit(
        propertyRepository: context.read<PropertyRepository>(),
        ownerId: context.read<ProfileCubit>().state.profile?.id ?? '',
        properties: context.read<SellerPropertiesCubit>().state.properties,
      ),
      child: const NewPropertyView(),
    );
  }
}

class NewPropertyView extends StatefulWidget {
  const new({super.key});

  @override
  State<NewPropertyView> createState() => _NewPropertyViewState();
}

class _NewPropertyViewState extends State<NewPropertyView> {
  final GlobalKey _typeKey = GlobalKey();

  Future<void> _onStatus(BuildContext context, NewPropertyState state) async {
    final l10n = context.l10n;
    switch (state.status) {
      case NewPropertyStatus.success:
        final property = state.property!;
        final properties = context.read<SellerPropertiesCubit>()
          ..propertyChanged(property, lot: state.lot);
        final router = GoRouter.of(context);
        // The partner joined the lot: reload the list (best effort).
        properties.refresh().ignore();
        router.go(SellerTunnelStep.owners.routeFor(property.id));
      case NewPropertyStatus.failure:
        showRealestySnackBar(context, l10n.newPropertyError, isError: true);
      case NewPropertyStatus.copyFailure:
        showRealestySnackBar(context, l10n.newPropertyCopyError, isError: true);
      case NewPropertyStatus.limitReached:
        showRealestySnackBar(
          context,
          l10n.myPropertiesLimit(PropertyRepository.maxProperties),
          isError: true,
        );
      case NewPropertyStatus.idle:
      case NewPropertyStatus.inProgress:
        break;
    }
  }

  void _revealType() {
    final target = _typeKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: RealestyMotion.page,
        alignment: 0.1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<NewPropertyCubit>();
    final state = context.watch<NewPropertyCubit>().state;
    final busy = state.isBusy;
    final source = state.source;
    return MultiBlocListener(
      listeners: [
        BlocListener<NewPropertyCubit, NewPropertyState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: _onStatus,
        ),
        BlocListener<NewPropertyCubit, NewPropertyState>(
          listenWhen: (previous, current) =>
              previous.submitAttempts != current.submitAttempts,
          listener: (context, state) => _revealType(),
        ),
      ],
      child: TunnelScaffold(
        spacing: 18,
        header: Row(
          spacing: RealestySpacing.xs,
          children: [
            RealestyIconButton(
              icon: RealestyIcons.chevronLeft,
              semanticLabel: l10n.backButtonLabel,
              onPressed: busy
                  ? null
                  : () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.seller),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.newPropertyTitle,
                  style: RealestyTextStyles.title2.copyWith(color: c.encre),
                ),
              ),
            ),
          ],
        ),
        actionBar: AgentActionBar(
          label: l10n.newPropertyStart,
          isLoading: busy,
          onPressed: cubit.submit,
        ),
        children: [
          AgentIntro(message: l10n.newPropertyIntro),
          Column(
            key: _typeKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              SectionLabel(l10n.newPropertyTypeLabel),
              SelectableCardGrid(
                spacing: 10,
                children: [
                  for (final type in PropertyType.values)
                    SelectableCard(
                      icon: propertyTypeIcon(type),
                      title: propertyTypeName(l10n, type),
                      subtitle: propertyTypeSubtitle(l10n, type),
                      selected: state.type == type,
                      onTap: busy ? null : () => cubit.typeSelected(type),
                    ),
                ],
              ),
              if (state.showErrors && state.typeMissing)
                Text(
                  l10n.newPropertyTypeError,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.erreur,
                  ),
                ),
            ],
          ),
          if (state.partners.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RealestySpacing.xs,
              children: [
                SectionLabel(l10n.newPropertyLotLabel),
                _Choices(
                  choices: [
                    (
                      label: l10n.newPropertyLotNone,
                      selected: state.partnerId == null,
                      onTap: () => cubit.partnerSelected(null),
                    ),
                    for (final partner in state.partners)
                      (
                        label: l10n.newPropertyLotWith(
                          propertyShortLabel(l10n, partner),
                        ),
                        selected: state.partnerId == partner.id,
                        onTap: () => cubit.partnerSelected(partner.id),
                      ),
                  ],
                  enabled: !busy,
                ),
              ],
            ),
          if (source != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RealestySpacing.xs,
              children: [
                SectionLabel(l10n.newPropertyReuseLabel),
                if (state.properties.length > 1)
                  _Choices(
                    choices: [
                      for (final property in state.properties)
                        (
                          label: l10n.newPropertyReuseFrom(
                            propertyShortLabel(l10n, property),
                          ),
                          selected: source.id == property.id,
                          onTap: () => cubit.sourceSelected(property.id),
                        ),
                    ],
                    enabled: !busy,
                  )
                else
                  Text(
                    l10n.newPropertyReuseFrom(propertyShortLabel(l10n, source)),
                    style: RealestyTextStyles.body.copyWith(color: c.encre),
                  ),
                RealestyCheckbox(
                  value: state.reuseOwners,
                  label: l10n.newPropertyReuseOwners,
                  onChanged: busy
                      ? null
                      : (value) => cubit.reuseOwnersChanged(reuse: value),
                ),
                RealestyCheckbox(
                  value: state.reuseIdentity,
                  label: l10n.newPropertyReuseIdentity,
                  onChanged: busy
                      ? null
                      : (value) => cubit.reuseIdentityChanged(reuse: value),
                ),
                Text(
                  l10n.newPropertyReuseHelp,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A choice among properties: one row each (labels can be long), the
/// selected one ticked.
class _Choices extends StatelessWidget {
  const new({required this.choices, required this.enabled});

  final List<({String label, bool selected, VoidCallback onTap})> choices;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        children: [
          for (final (index, choice) in choices.indexed)
            Semantics(
              selected: choice.selected,
              child: RealestyListItem(
                title: choice.label,
                showDivider: index < choices.length - 1,
                onTap: enabled ? choice.onTap : null,
                trailing: choice.selected
                    ? RealestyIcon(RealestyIcons.check, color: c.vertTexte)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
