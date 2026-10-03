import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/account_deletion/cubit/account_deletion_cubit.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/account/widgets/account_screen.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:profile_repository/profile_repository.dart';

/// Supprimer mon compte (EPIC-11, US-11.9, not designed; App Store rule
/// 5.1.1(v)): what will be deleted, the 30-day delay, the blockers (a sale
/// in progress, a team account), the typed confirmation, then the
/// deactivation and the sign-out.
class AccountDeletionPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = AccountDeletionCubit(
          profileRepository: context.read<ProfileRepository>(),
          authRepository: context.read<AuthRepository>(),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const AccountDeletionView(),
    );
  }
}

class AccountDeletionView extends StatelessWidget {
  const new({super.key});

  String _home(BuildContext context) =>
      switch (context.read<ProfileCubit>().state.profile?.role) {
        UserRole.buyer => AppRoutes.buyer,
        UserRole.seller => AppRoutes.sellerAccount,
        null => AppRoutes.role,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<AccountDeletionCubit>().state;
    final cubit = context.read<AccountDeletionCubit>();
    if (state.status == AccountDeletionStatus.deactivated) {
      return AccountScreen(
        title: l10n.deleteAccountDoneTitle,
        onBack: cubit.finish,
        bottom: RealestyButton(
          label: l10n.deleteAccountDoneButton,
          onPressed: cubit.finish,
        ),
        children: [
          InlineBanner(
            message: l10n.deleteAccountDoneMessage(
              fullDate(state.deletionDueAt!),
            ),
            variant: InlineBannerVariant.info,
          ),
          const SizedBox(height: RealestySpacing.md),
          Text(
            l10n.deleteAccountDoneReactivate,
            style: RealestyTextStyles.body.copyWith(color: c.encre2),
          ),
        ],
      );
    }
    final busy = state.status == AccountDeletionStatus.deactivating;
    final loading =
        state.status == AccountDeletionStatus.initial ||
        state.status == AccountDeletionStatus.loading;
    final word = l10n.deleteAccountWord;
    return AccountScreen(
      title: l10n.deleteAccountTitle,
      fallbackLocation: _home(context),
      bottom: RealestyButton(
        label: l10n.deleteAccountButton,
        variant: RealestyButtonVariant.destructive,
        isLoading: busy,
        onPressed:
            busy ||
                loading ||
                state.isBlocked ||
                state.status == AccountDeletionStatus.loadFailure
            ? null
            : () => cubit.deactivate(word),
      ),
      children: [
        Text(
          l10n.deleteAccountIntro,
          style: RealestyTextStyles.body.copyWith(color: c.encre),
        ),
        const SizedBox(height: RealestySpacing.md),
        _Card(
          children: [
            for (final item in [
              l10n.deleteAccountItemProfile,
              l10n.deleteAccountItemProperties,
              l10n.deleteAccountItemDocuments,
              l10n.deleteAccountItemValuations,
              l10n.deleteAccountItemNotifications,
              l10n.deleteAccountItemVoice,
            ])
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: RealestySpacing.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: RealestySpacing.xs,
                  children: [
                    RealestyIcon(
                      RealestyIcons.trash,
                      size: 18,
                      color: c.erreur,
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: RealestyTextStyles.body.copyWith(color: c.encre),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: RealestySpacing.md),
        InlineBanner(
          message: l10n.deleteAccountDelay,
          variant: InlineBannerVariant.info,
          icon: RealestyIcons.clock,
        ),
        const SizedBox(height: RealestySpacing.md),
        if (loading)
          Padding(
            padding: const EdgeInsets.all(RealestySpacing.md),
            child: Center(child: CircularProgressIndicator(color: c.vertTexte)),
          )
        else if (state.status == AccountDeletionStatus.loadFailure) ...[
          InlineBanner(message: l10n.deleteAccountLoadFailed),
          const SizedBox(height: RealestySpacing.sm),
          RealestyButton(
            label: l10n.vaultRetry,
            variant: RealestyButtonVariant.secondary,
            onPressed: cubit.load,
          ),
        ] else if (state.blockers.contains(AccountDeletionBlocker.staffAccount))
          InlineBanner(message: l10n.deleteAccountStaff)
        else if (state.blockers.contains(
          AccountDeletionBlocker.activeSale,
        )) ...[
          InlineBanner(message: l10n.deleteAccountActiveSale),
          const SizedBox(height: RealestySpacing.sm),
          RealestyButton(
            label: l10n.deleteAccountWithdrawSale,
            variant: RealestyButtonVariant.secondary,
            onPressed: () => context.go(AppRoutes.seller),
          ),
        ] else ...[
          Text(
            l10n.deleteAccountConfirmLabel(word),
            style: RealestyTextStyles.body.copyWith(color: c.encre),
          ),
          const SizedBox(height: RealestySpacing.xs),
          RealestyTextField(
            label: l10n.deleteAccountConfirmField,
            hint: word,
            enabled: !busy,
            autofillHints: const [],
            errorText: state.showErrors
                ? l10n.deleteAccountConfirmError(word)
                : null,
            onChanged: cubit.confirmationChanged,
            onSubmitted: (_) => cubit.deactivate(word),
          ),
          if (state.status == AccountDeletionStatus.deactivateFailure) ...[
            const SizedBox(height: RealestySpacing.sm),
            InlineBanner(message: l10n.deleteAccountFailed),
          ],
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RealestySpacing.md,
        vertical: RealestySpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
