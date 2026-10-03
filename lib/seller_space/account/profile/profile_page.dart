import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/account/profile/cubit/profile_form_cubit.dart';
import 'package:mobileapp/seller_space/account/widgets/account_screen.dart';
import 'package:mobileapp/seller_space/account/widgets/account_section.dart';
import 'package:mobileapp/seller_space/vault/models/vault_contents.dart';
import 'package:mobileapp/seller_space/vault/models/vault_rubric.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';

/// V19 · Informations & sécurité: the personal information of the user
/// (the e-mail is read-only), the owners of the property with the status
/// of their identity document, the sign-in method and "Supprimer mon
/// compte".
class ProfilePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.read<ProfileCubit>().state.profile;
    if (profile == null) return const SizedBox.shrink();
    return BlocProvider(
      create: (context) => ProfileFormCubit(
        profileRepository: context.read<ProfileRepository>(),
        profile: profile,
      ),
      child: const ProfileView(),
    );
  }
}

class ProfileView extends StatefulWidget {
  const new({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final ProfileFormState _initial = context.read<ProfileFormCubit>().state;
  late final _firstName = TextEditingController(text: _initial.firstName);
  late final _lastName = TextEditingController(text: _initial.lastName);
  late final _phone = TextEditingController(text: _initial.phone);
  late final _address = TextEditingController(text: _initial.postalAddress);
  late final _email = TextEditingController(
    text: context.read<AppBloc>().state.user?.email ?? '',
  );
  final Map<_Field, GlobalKey> _keys = {
    for (final field in _Field.values) field: GlobalKey(),
  };

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _address.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    FocusScope.of(context).unfocus();
    final cubit = context.read<ProfileFormCubit>();
    await cubit.save();
    if (!mounted) return;
    final state = cubit.state;
    if (state.status == ProfileFormStatus.saved) {
      context.read<ProfileCubit>().profileUpdated(state.profile);
      showRealestySnackBar(context, l10n.profileSaved);
      return;
    }
    if (state.status == ProfileFormStatus.failure) {
      showRealestySnackBar(context, l10n.profileSaveFailed, isError: true);
      return;
    }
    final first = <_Field, ProfileFieldError?>{
      _Field.firstName: state.firstNameError,
      _Field.lastName: state.lastNameError,
      _Field.phone: state.phoneError,
      _Field.address: state.postalAddressError,
    }.entries.firstWhere((entry) => entry.value != null).key;
    final target = _keys[first]!.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: RealestyMotion.page,
        alignment: 0.2,
      );
    }
  }

  Future<void> _leave() async {
    final l10n = context.l10n;
    if (!context.read<ProfileFormCubit>().state.isDirty) {
      AccountScreen.back(context, AppRoutes.sellerAccount);
      return;
    }
    final leave = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          0,
          RealestySpacing.gutter,
          RealestySpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.sm,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.profileLeaveTitle,
                style: RealestyTextStyles.title2,
              ),
            ),
            Text(l10n.profileLeaveMessage, style: RealestyTextStyles.body),
            const SizedBox(height: RealestySpacing.xs),
            RealestyButton(
              label: l10n.profileLeaveStay,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            RealestyButton(
              label: l10n.profileLeaveConfirm,
              variant: RealestyButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if ((leave ?? false) && mounted) {
      AccountScreen.back(context, AppRoutes.sellerAccount);
    }
  }

  String? _error(ProfileFormState state, ProfileFieldError? error) {
    if (!state.showErrors || error == null) return null;
    final l10n = context.l10n;
    return switch (error) {
      ProfileFieldError.tooLong => l10n.profileErrorTooLong,
      ProfileFieldError.invalidPhone => l10n.profileErrorPhone,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<ProfileFormCubit>().state;
    final cubit = context.read<ProfileFormCubit>();
    final saving = state.status == ProfileFormStatus.saving;
    final tunnel = context.watch<SellerTunnelCubit?>()?.state;
    final property = tunnel?.property;
    final name = state.profile.fullName;
    return PopScope(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: AccountScreen(
        title: l10n.profileTitle,
        eyebrow: l10n.accountTitle,
        onBack: _leave,
        bottom: RealestyButton(
          label: l10n.profileSave,
          isLoading: saving,
          onPressed: saving ? null : _save,
        ),
        children: [
          Center(
            child: InitialsAvatar(
              name == null ? '?' : InitialsAvatar.of(name),
              size: 72,
            ),
          ),
          AccountSection(
            title: l10n.profileInformationSection,
            children: [
              const SizedBox(height: RealestySpacing.sm),
              RealestyTextField(
                key: _keys[_Field.firstName],
                label: l10n.profileFirstName,
                controller: _firstName,
                enabled: !saving,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.givenName],
                errorText: _error(state, state.firstNameError),
                onChanged: cubit.firstNameChanged,
              ),
              const SizedBox(height: RealestySpacing.sm),
              RealestyTextField(
                key: _keys[_Field.lastName],
                label: l10n.profileLastName,
                controller: _lastName,
                enabled: !saving,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.familyName],
                errorText: _error(state, state.lastNameError),
                onChanged: cubit.lastNameChanged,
              ),
              const SizedBox(height: RealestySpacing.sm),
              RealestyTextField(
                label: l10n.profileEmail,
                controller: _email,
                enabled: false,
                leadingIcon: RealestyIcons.lock,
                footer: Text(
                  l10n.profileEmailHelp,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ),
              const SizedBox(height: RealestySpacing.sm),
              RealestyTextField(
                key: _keys[_Field.phone],
                label: l10n.profilePhone,
                hint: l10n.profilePhoneHint,
                controller: _phone,
                enabled: !saving,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                errorText: _error(state, state.phoneError),
                onChanged: cubit.phoneChanged,
              ),
              const SizedBox(height: RealestySpacing.sm),
              RealestyTextField(
                key: _keys[_Field.address],
                label: l10n.profileAddress,
                hint: l10n.profileAddressHint,
                controller: _address,
                enabled: !saving,
                maxLines: 3,
                autofillHints: const [AutofillHints.fullStreetAddress],
                errorText: _error(state, state.postalAddressError),
                onChanged: cubit.postalAddressChanged,
              ),
              const SizedBox(height: RealestySpacing.md),
            ],
          ),
          if (property != null && tunnel!.owners.isNotEmpty)
            AccountSection(
              title: l10n.profileOwnersSection,
              children: [
                for (final (index, owner) in tunnel.owners.indexed)
                  _OwnerRow(
                    owner: owner,
                    isUser: owner.profileId == state.profile.id,
                    received: _identityReceived(
                      property,
                      tunnel.owners,
                      tunnel.documents,
                      owner,
                    ),
                    showDivider: index < tunnel.owners.length - 1,
                    onTap: () => context.go(
                      AppRoutes.sellerVaultProperty(
                        property.id,
                        rubric: VaultRubric.identity.code,
                      ),
                    ),
                  ),
              ],
            ),
          AccountSection(
            title: l10n.profileSecuritySection,
            children: [
              RealestyListItem(
                title: l10n.accountSignInMethod,
                subtitle: l10n.accountSignInMethodValue,
                leadingIcon: RealestyIcons.mail,
                showDivider: property != null,
              ),
              if (property != null)
                RealestyListItem(
                  title: l10n.profileIdentity,
                  subtitle: l10n.profileIdentitySubtitle,
                  leadingIcon: RealestyIcons.user,
                  showDivider: false,
                  trailing: _identityMissing(tunnel!)
                      ? RealestyBadge(
                          label: l10n.profileIdentityToAdd,
                          variant: RealestyBadgeVariant.toComplete,
                        )
                      : RealestyBadge(
                          label: l10n.profileIdentityReceived,
                          variant: RealestyBadgeVariant.certified,
                        ),
                  onTap: () => context.go(
                    AppRoutes.sellerVaultProperty(
                      property.id,
                      rubric: VaultRubric.identity.code,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: RealestySpacing.lg),
          Center(
            child: RealestyPressable(
              semanticLabel: l10n.profileDeleteAccount,
              onPressed: () => context.push(AppRoutes.accountDeletion),
              child: Padding(
                padding: const EdgeInsets.all(RealestySpacing.sm),
                child: Text(
                  l10n.profileDeleteAccount,
                  style: RealestyTextStyles.button.copyWith(color: c.erreur),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _identityReceived(
    Property property,
    List<PropertyOwner> owners,
    List<PropertyDocument> documents,
    PropertyOwner owner,
  ) => !VaultContents.of(
    properties: [property],
    documents: documents,
    owners: {property.id: owners},
  ).missing.any((entry) => entry.owner?.id == owner.id);

  static bool _identityMissing(SellerTunnelState tunnel) => VaultContents.of(
    properties: [tunnel.property!],
    documents: tunnel.documents,
    owners: {tunnel.property!.id: tunnel.owners},
  ).missing.any((entry) => entry.kind == DocumentKind.identityDocument);
}

enum _Field { firstName, lastName, phone, address }

class _OwnerRow extends StatelessWidget {
  const new({
    required this.owner,
    required this.isUser,
    required this.received,
    required this.showDivider,
    required this.onTap,
  });

  final PropertyOwner owner;
  final bool isUser;
  final bool received;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = '${owner.firstName} ${owner.lastName}'.trim();
    return RealestyListItem(
      title: isUser ? l10n.profileOwnerYou(name) : name,
      subtitle: received
          ? l10n.profileIdentityReceivedSubtitle
          : l10n.profileIdentityMissingSubtitle,
      leadingIcon: RealestyIcons.user,
      tone: received
          ? RealestyListTileTone.success
          : RealestyListTileTone.neutral,
      showDivider: showDivider,
      trailing: RealestyBadge(
        label: received
            ? l10n.profileIdentityReceived
            : l10n.profileIdentityToAdd,
        variant: received
            ? RealestyBadgeVariant.certified
            : RealestyBadgeVariant.toComplete,
      ),
      onTap: onTap,
    );
  }
}
