import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubits.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_shell.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:mobileapp/ui/ui.dart';

/// Wraps a screen of the property [propertyId] (`/vendeur/biens/<id>/…`):
/// provides its [SellerTunnelCubit] (from [SellerTunnelCubits]) and shows
/// [child] once the dossier is loaded — a spinner while it loads, an error
/// with retry otherwise (back to the seller space when the property no
/// longer exists). Screens can therefore rely on
/// `SellerTunnelState.property` being set.
///
/// For a tunnel screen, [auditSegment] is its last path segment: a sent
/// dossier redirects its editable steps to V8, and a step its type skips to
/// the next one (`SellerTunnelState.redirectFor`).
///
/// Also reacts to saves (on the visible screen only): opens `nextStep`
/// after a successful `saveAndContinue` (if the user is still on the saved
/// step) and shows a snackbar when a save failed.
class PropertyRouteScope extends StatelessWidget {
  const new({
    required this.propertyId,
    required this.child,
    this.auditSegment,
    super.key,
  });

  final String propertyId;
  final String? auditSegment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: context.read<SellerTunnelCubits>().of(propertyId),
      child: PropertyGate(auditSegment: auditSegment, child: child),
    );
  }
}

/// Provides the [SellerTunnelCubit] of the seller's first property to
/// [child], without waiting for it (screens outside a property, such as
/// the "Compte" tab, that show the main owner's name once known).
class FirstPropertyScope extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = context.select<SellerPropertiesCubit, String?>(
      (cubit) => cubit.state.properties.firstOrNull?.id,
    );
    if (id == null) return child;
    return BlocProvider.value(
      value: context.read<SellerTunnelCubits>().of(id),
      child: child,
    );
  }
}

/// The loading / redirect / save logic of [PropertyRouteScope], under the
/// [SellerTunnelCubit] of the property.
class PropertyGate extends StatelessWidget {
  const new({required this.child, this.auditSegment, super.key});

  final String? auditSegment;
  final Widget child;

  /// Whether this screen is the one the user sees (not covered by another
  /// route, not in another tab).
  static bool _isVisible(BuildContext context) =>
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SellerTunnelCubit>().state;
    final segment = auditSegment;
    final redirect =
        state.status == SellerTunnelStatus.success && segment != null
        ? state.redirectFor(segment)
        : null;
    if (redirect != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && _isVisible(context)) context.go(redirect);
      });
    }
    return BlocListener<SellerTunnelCubit, SellerTunnelState>(
      listenWhen: (previous, current) =>
          previous.saveStatus != current.saveStatus,
      listener: (context, state) {
        if (!_isVisible(context)) return;
        switch (state.saveStatus) {
          case SellerTunnelSaveStatus.success:
            final next = state.nextStep;
            final id = state.property!.id;
            // Only if the user is still on the step that was saved (they
            // may have gone back while it was saving).
            if (next != null &&
                GoRouter.of(context).state.matchedLocation ==
                    state.continuedFrom?.routeFor(id)) {
              // V3 → V4 (voice audit) when voice is available for this
              // type; V4 falls back to V4b (screen mode) without consent.
              if (next == SellerTunnelStep.technical &&
                  state.profile.voiceAudit &&
                  VoiceServices.of(context).isAvailable) {
                context.go(
                  AppRoutes.sellerPropertyAudit(
                    id,
                    SellerTunnelStep.voiceAuditSegment,
                  ),
                );
              } else {
                context.goToTunnelStep(next);
              }
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
      child: switch (state.status) {
        SellerTunnelStatus.success when redirect != null =>
          const SellerLoading(),
        SellerTunnelStatus.success => child,
        SellerTunnelStatus.failure => _PropertyLoadFailure(
          notFound: state.notFound,
        ),
        SellerTunnelStatus.initial ||
        SellerTunnelStatus.loading => const SellerLoading(),
      },
    );
  }
}

class _PropertyLoadFailure extends StatelessWidget {
  const new({required this.notFound});

  /// The property no longer exists (deleted on another device, or a stale
  /// link): back to the seller space.
  final bool notFound;

  @override
  Widget build(BuildContext context) {
    if (notFound) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.read<SellerPropertiesCubit?>()?.refresh().ignore();
        context.go(AppRoutes.seller);
      });
      return const SellerLoading();
    }
    return SellerLoadFailure(
      onRetry: () => context.read<SellerTunnelCubit>().retry(),
    );
  }
}
