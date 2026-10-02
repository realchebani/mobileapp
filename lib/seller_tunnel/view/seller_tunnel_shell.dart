import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubits.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Wraps every `/vendeur` screen (shell route): creates the
/// [SellerPropertiesCubit] of the signed-in seller (loads the properties
/// and lots, and creates the first property of a new seller) and the
/// [SellerTunnelCubits] of the properties opened (see `PropertyRouteScope`).
class SellerTunnelShell extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = SellerPropertiesCubit(
          propertyRepository: context.read<PropertyRepository>(),
          ownerId: context.read<ProfileCubit>().state.profile?.id ?? '',
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: RepositoryProvider(
        create: (context) => SellerTunnelCubits(
          propertyRepository: context.read<PropertyRepository>(),
          onPropertyChanged: context
              .read<SellerPropertiesCubit>()
              .propertyChanged,
        ),
        dispose: (cubits) => unawaited(cubits.close()),
        child: SellerPropertiesGate(child: child),
      ),
    );
  }
}

/// Shows [child] once the seller's properties are loaded; a spinner while
/// they load, and an error with retry / sign out when it failed.
class SellerPropertiesGate extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final status = context
        .select<SellerPropertiesCubit, SellerPropertiesStatus>(
          (cubit) => cubit.state.status,
        );
    final loaded = context.select<SellerPropertiesCubit, bool>(
      (cubit) => cubit.state.properties.isNotEmpty,
    );
    // A failed refresh keeps the loaded list: only a first load blocks.
    if (loaded) return child;
    return switch (status) {
      SellerPropertiesStatus.failure => SellerLoadFailure(
        onRetry: () => context.read<SellerPropertiesCubit>().load(),
      ),
      _ => const SellerLoading(),
    };
  }
}

/// Full screen spinner of the seller space.
class SellerLoading extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Scaffold(
      backgroundColor: c.ivoire,
      body: Center(child: CircularProgressIndicator(color: c.vertTexte)),
    );
  }
}

/// Full screen loading error of the seller space: retry or sign out.
class SellerLoadFailure extends StatelessWidget {
  const new({required this.onRetry, super.key});

  final VoidCallback onRetry;

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
              RealestyButton(label: l10n.retryButton, onPressed: onRetry),
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
