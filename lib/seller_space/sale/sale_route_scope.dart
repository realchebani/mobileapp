import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubits.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_shell.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Provides the [SaleCubit] of the sale [saleId] (shared by every screen of
/// the sale, see [SaleCubits]) and shows [child] once the sale is loaded:
/// a spinner meanwhile, an error with retry, or a message when the sale
/// does not exist (any more), was withdrawn, or sales are not available.
class SaleRouteScope extends StatelessWidget {
  const new({required this.saleId, required this.child, super.key});

  final String saleId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final SaleCubits cubits;
    try {
      cubits = context.read<SaleCubits>();
    } on ProviderNotFoundException {
      return _SaleMessage(message: context.l10n.saleUnavailable);
    }
    return BlocProvider.value(
      value: cubits.of(saleId),
      child: SaleGate(child: child),
    );
  }
}

/// [child] once the sale of the [SaleCubit] above is loaded and active.
class SaleGate extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<SaleCubit>().state;
    final sale = state.sale;
    if (sale != null) {
      if (sale.stage == SaleStage.withdrawn) {
        return _SaleMessage(message: l10n.saleWithdrawnMessage);
      }
      return child;
    }
    return switch (state.status) {
      SaleLoadStatus.notFound => _SaleMessage(message: l10n.saleNotFound),
      SaleLoadStatus.failure => _SaleMessage(
        message: l10n.saleLoadError,
        onRetry: () => context.read<SaleCubit>().refresh(),
      ),
      _ => const SellerLoading(),
    };
  }
}

class _SaleMessage extends StatelessWidget {
  const new({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final onRetry = this.onRetry;
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
                message,
                textAlign: TextAlign.center,
                style: RealestyTextStyles.body.copyWith(color: c.encre),
              ),
              if (onRetry != null)
                RealestyButton(label: l10n.retryButton, onPressed: onRetry),
              RealestyButton(
                label: l10n.saleBackHome,
                variant: RealestyButtonVariant.secondary,
                onPressed: () => context.go(AppRoutes.seller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
