import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Wraps every `/vendeur` screen (shell route): creates the
/// [SellerTunnelCubit] of the signed-in user and loads the dossier.
class SellerTunnelShell extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = SellerTunnelCubit(
          propertyRepository: context.read<PropertyRepository>(),
          ownerId: context.read<ProfileCubit>().state.profile?.id ?? '',
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: SellerTunnelGate(child: child),
    );
  }
}

/// Shows [child] once the dossier is loaded; a spinner while it loads, and
/// an error with retry / sign out when it failed. Step screens can
/// therefore rely on `SellerTunnelState.property` being set.
///
/// Also reacts to saves: opens `nextStep` after a successful
/// `saveAndContinue` (if the user is still on the saved step) and shows a
/// snackbar when a save failed.
///
/// Once the dossier is sent (`SellerTunnelState.isLocked`), the editable
/// steps redirect to V8 (`SellerTunnelState.lockRedirect`).
class SellerTunnelGate extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (status, isLocked) = context
        .select<SellerTunnelCubit, (SellerTunnelStatus, bool)>(
          (cubit) => (cubit.state.status, cubit.state.isLocked),
        );
    final lockRedirect = status == SellerTunnelStatus.success && isLocked
        ? context.read<SellerTunnelCubit>().state.lockRedirect(
            GoRouter.of(context).state.matchedLocation,
          )
        : null;
    if (lockRedirect != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(lockRedirect);
      });
    }
    return BlocListener<SellerTunnelCubit, SellerTunnelState>(
      listenWhen: (previous, current) =>
          previous.saveStatus != current.saveStatus,
      listener: (context, state) {
        switch (state.saveStatus) {
          case SellerTunnelSaveStatus.success:
            final next = state.nextStep;
            // Only if the user is still on the step that was saved (they
            // may have gone back while it was saving).
            if (next != null &&
                GoRouter.of(context).state.matchedLocation ==
                    state.continuedFrom?.path) {
              context.goToTunnelStep(next);
            }
          case SellerTunnelSaveStatus.failure:
            showRealestySnackBar(
              context,
              context.l10n.sellerTunnelSaveError,
              isError: true,
            );
          case SellerTunnelSaveStatus.idle:
          case SellerTunnelSaveStatus.inProgress:
            break;
        }
      },
      child: switch (status) {
        SellerTunnelStatus.success when lockRedirect != null =>
          const _Loading(),
        SellerTunnelStatus.success => child,
        SellerTunnelStatus.failure => const _LoadFailure(),
        SellerTunnelStatus.initial ||
        SellerTunnelStatus.loading => const _Loading(),
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Scaffold(
      backgroundColor: c.ivoire,
      body: Center(child: CircularProgressIndicator(color: c.vertTexte)),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Scaffold(
      backgroundColor: c.ivoire,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RealestySpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              Text(
                l10n.sellerTunnelLoadError,
                textAlign: TextAlign.center,
                style: RealestyTextStyles.body.copyWith(color: c.encre),
              ),
              const SizedBox(height: RealestySpacing.sm),
              RealestyButton(
                label: l10n.retryButton,
                onPressed: () => context.read<SellerTunnelCubit>().retry(),
              ),
              RealestyButton(
                label: l10n.logoutButton,
                variant: RealestyButtonVariant.text,
                onPressed: () =>
                    context.read<AppBloc>().add(const AppLogoutPressed()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
