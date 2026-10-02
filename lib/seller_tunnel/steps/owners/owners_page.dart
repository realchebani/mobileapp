import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/cubit/owners_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/co_owner_card.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/co_owner_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/owner_field_error_text.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/owners_copied_note.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V1 · Identification des propriétaires: ownership situation, the user
/// (owner 1, prefilled from the profile and the account e-mail) and the
/// co-owners.
class OwnersPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final tunnel = context.read<SellerTunnelCubit>().state;
        final property = tunnel.property!;
        return OwnersCubit(
          propertyRepository: context.read<PropertyRepository>(),
          propertyId: property.id,
          profileId: property.ownerId,
          owners: tunnel.owners,
          ownershipType: property.ownershipType,
          firstName: context.read<ProfileCubit>().state.profile?.firstName,
          email: context.read<AppBloc>().state.user?.email,
        );
      },
      child: const OwnersView(),
    );
  }
}

/// The V1 form, driven by [OwnersCubit]. "Continuer" saves the owners,
/// reports them to the [SellerTunnelCubit] and saves the ownership type
/// (the tunnel then opens V2).
class OwnersView extends StatefulWidget {
  const new({super.key});

  @override
  State<OwnersView> createState() => _OwnersViewState();
}

class _OwnersViewState extends State<OwnersView> {
  late final OwnerDraft _initial = context.read<OwnersCubit>().state.owner;
  late final _firstName = TextEditingController(text: _initial.firstName);
  late final _lastName = TextEditingController(text: _initial.lastName);
  late final _phone = TextEditingController(text: _initial.phone);
  late final _email = TextEditingController(text: _initial.email);
  late final Map<OwnerField, FocusNode> _focusNodes = {
    for (final field in OwnerField.values)
      field: FocusNode()..addListener(() => _focusChanged(field)),
  };
  final GlobalKey _ownershipKey = GlobalKey();
  late final Map<OwnerField, GlobalKey> _fieldKeys = {
    for (final field in OwnerField.values) field: GlobalKey(),
  };
  final GlobalKey _coOwnersKey = GlobalKey();

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusChanged(OwnerField field) {
    if (mounted && !_focusNodes[field]!.hasFocus) {
      context.read<OwnersCubit>().fieldLeft(field);
    }
  }

  Future<void> _addCoOwner() async {
    final result = await showCoOwnerSheet(context);
    if (result is! CoOwnerSaved || !mounted) return;
    context.read<OwnersCubit>().coOwnerAdded(result.coOwner);
  }

  Future<void> _editCoOwner(int index, OwnerDraft initial) async {
    final result = await showCoOwnerSheet(context, initial: initial);
    if (!mounted) return;
    final cubit = context.read<OwnersCubit>();
    switch (result) {
      case CoOwnerSaved(:final coOwner):
        cubit.coOwnerEdited(index, coOwner);
      case CoOwnerDeleted():
        cubit.coOwnerRemoved(index);
      case null:
        break;
    }
  }

  /// The V1 voice sheet (EPIC-14): ownership and co-owners' names.
  Future<void> _openVoiceSheet() async {
    final l10n = context.l10n;
    await showStepVoiceSheet(
      context,
      propertyId: context.read<SellerTunnelCubit>().state.property!.id,
      step: AgentStep.owners,
      form: context.read<OwnersCubit>(),
      title: l10n.ownersVoiceTitle,
      intro: ownersVoiceIntro(l10n, names: VoiceDefaults.coOwnerNames),
    );
  }

  /// Scrolls to the first missing or invalid answer.
  void _revealFirstError(BuildContext context, OwnersState state) {
    final field = OwnerField.values
        .where((field) => state.errorOf(field) != null)
        .firstOrNull;
    final key = state.ownershipMissing
        ? _ownershipKey
        : field != null
        ? _fieldKeys[field]!
        : _coOwnersKey;
    // After the frame, so that the error messages are laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: RealestyMotion.page,
          alignment: 0.1,
        );
      }
    });
  }

  void _submitted(BuildContext context, OwnersState state) {
    switch (state.submitStatus) {
      case OwnersSubmitStatus.success:
        final tunnel = context.read<SellerTunnelCubit>()
          ..updateChildren(owners: state.saved);
        unawaited(
          tunnel.saveAndContinue(SellerTunnelStep.owners, {
            PropertyColumns.ownershipType: state.submittedOwnershipType,
          }),
        );
      case OwnersSubmitStatus.failure:
        showRealestySnackBar(
          context,
          context.l10n.sellerTunnelSaveError,
          isError: true,
        );
      case OwnersSubmitStatus.idle:
      case OwnersSubmitStatus.inProgress:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<OwnersCubit>().state;
    final cubit = context.read<OwnersCubit>();
    final tunnelSaving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    final isBusy = state.isSubmitting || tunnelSaving;
    String? error(OwnerField field) => state.errorOf(field)?.message(l10n);
    final nameFormatters = [
      LengthLimitingTextInputFormatter(ownerNameMaxLength),
    ];
    final voice =
        VoiceServices.of(context).isAvailable &&
        context.select<SellerTunnelCubit, bool>(
          (cubit) => cubit.state.profile.hasVoice(SellerTunnelStep.owners),
        );

    return MultiBlocListener(
      listeners: [
        BlocListener<OwnersCubit, OwnersState>(
          listenWhen: (previous, current) =>
              previous.submitStatus != current.submitStatus,
          listener: _submitted,
        ),
        BlocListener<OwnersCubit, OwnersState>(
          listenWhen: (previous, current) =>
              previous.submitAttempts != current.submitAttempts,
          listener: _revealFirstError,
        ),
      ],
      child: TunnelScaffold(
        header: TunnelHeader(
          step: SellerTunnelStep.owners,
          onBack: () => context.goBackFrom(SellerTunnelStep.owners),
        ),
        actionBar: AgentActionBar(
          hint: l10n.tunnelHintVoiceOrScreen,
          label: l10n.tunnelContinue,
          isLoading: isBusy,
          onPressed: cubit.submit,
          onMicPressed: isBusy || !voice
              ? null
              : () => unawaited(_openVoiceSheet()),
        ),
        children: [
          AgentIntro(message: l10n.ownersIntro),
          if (context.select<SellerTunnelCubit, bool>(
            (cubit) => cubit.state.property?.ownersCopiedFrom != null,
          ))
            const OwnersCopiedNote(),
          Column(
            key: _ownershipKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.xs,
            children: [
              SelectableCardGrid(
                children: [
                  SelectableCard(
                    icon: RealestyIcons.user,
                    title: l10n.ownersSingleTitle,
                    selected: state.ownershipType == OwnershipType.single,
                    onTap: isBusy
                        ? null
                        : () => cubit.ownershipSelected(OwnershipType.single),
                  ),
                  SelectableCard(
                    icon: RealestyIcons.users,
                    title: l10n.ownersMultipleTitle,
                    subtitle: l10n.ownersMultipleSubtitle,
                    selected: state.isMultiple,
                    onTap: isBusy
                        ? null
                        : () => cubit.ownershipSelected(OwnershipType.multiple),
                  ),
                ],
              ),
              if (state.ownershipMissing) _FormError(l10n.ownersErrorOwnership),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              SectionLabel(l10n.ownersOwnerOneLabel),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: RealestySpacing.sm,
                children: [
                  Expanded(
                    child: RealestyTextField(
                      label: l10n.ownersFirstNameLabel,
                      key: _fieldKeys[OwnerField.firstName],
                      controller: _firstName,
                      enabled: !isBusy,
                      focusNode: _focusNodes[OwnerField.firstName],
                      textInputAction: TextInputAction.next,
                      inputFormatters: nameFormatters,
                      autofillHints: const [AutofillHints.givenName],
                      onChanged: cubit.firstNameChanged,
                      errorText: error(OwnerField.firstName),
                    ),
                  ),
                  Expanded(
                    child: RealestyTextField(
                      label: l10n.ownersLastNameLabel,
                      key: _fieldKeys[OwnerField.lastName],
                      controller: _lastName,
                      enabled: !isBusy,
                      focusNode: _focusNodes[OwnerField.lastName],
                      textInputAction: TextInputAction.next,
                      inputFormatters: nameFormatters,
                      autofillHints: const [AutofillHints.familyName],
                      onChanged: cubit.lastNameChanged,
                      errorText: error(OwnerField.lastName),
                    ),
                  ),
                ],
              ),
              RealestyTextField(
                label: l10n.ownersPhoneLabel,
                hint: l10n.ownersPhoneHint,
                leadingIcon: RealestyIcons.phone,
                key: _fieldKeys[OwnerField.phone],
                controller: _phone,
                enabled: !isBusy,
                focusNode: _focusNodes[OwnerField.phone],
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                onChanged: cubit.phoneChanged,
                errorText: error(OwnerField.phone),
              ),
              RealestyTextField(
                label: l10n.ownersEmailLabel,
                hint: l10n.ownersEmailHint,
                leadingIcon: RealestyIcons.chat,
                key: _fieldKeys[OwnerField.email],
                controller: _email,
                enabled: !isBusy,
                focusNode: _focusNodes[OwnerField.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                onChanged: cubit.emailChanged,
                errorText: error(OwnerField.email),
              ),
            ],
          ),
          if (state.isMultiple) ...[
            for (final (index, coOwner) in state.coOwners.indexed)
              CoOwnerCard(
                coOwner: coOwner,
                dictated: state.dictated.contains('co_owner:$index'),
                incomplete: state.coOwnerIncomplete(index),
                onEdit: isBusy ? null : () => _editCoOwner(index, coOwner),
              ),
            if (state.coOwnersMissing) _FormError(l10n.ownersErrorCoOwners),
            RealestyButton(
              key: _coOwnersKey,
              label: l10n.ownersAddCoOwner,
              variant: RealestyButtonVariant.text,
              leadingIcon: RealestyIcons.plus,
              height: RealestySpacing.minTouchTarget,
              onPressed: isBusy ? null : _addCoOwner,
            ),
          ],
        ],
      ),
    );
  }
}

/// The intro of the V1 voice sheet: with the co-owners' names when they
/// can be dictated (owner decision Q1).
String ownersVoiceIntro(AppLocalizations l10n, {required bool names}) =>
    names ? l10n.ownersVoiceIntro : l10n.ownersVoiceIntroWithoutNames;

/// Error under a group of answers, styled like the text field errors.
class _FormError extends StatelessWidget {
  const new(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: RealestyIcon(
              RealestyIcons.infoCircle,
              size: 14,
              color: c.erreur,
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
            ),
          ),
        ],
      ),
    );
  }
}
