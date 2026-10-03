import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubits.dart';
import 'package:mobileapp/seller_space/sale/cubit/sales_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// The sale repository, or null when sales are not available (flavor
/// without `SALES_ENABLED`: no repository provided by `App`).
SaleRepository? saleRepositoryOf(BuildContext context) {
  try {
    return context.read<SaleRepository>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// The [SalesCubit] above [context], or null when sales are not available.
SalesCubit? salesCubitOf(BuildContext context) {
  try {
    return context.read<SalesCubit>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Provides the [SalesCubit] of the signed-in seller (loaded on first use)
/// and the [SaleCubits] of the sales opened to [child] when sales are
/// available; [child] alone otherwise. Placed under the seller's
/// properties (`SellerTunnelShell`).
class SalesScope extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final repository = saleRepositoryOf(context);
    if (repository == null) return child;
    final ownerId = context.read<ProfileCubit>().state.profile?.id ?? '';
    return BlocProvider(
      create: (context) {
        final cubit = SalesCubit(repository: repository, ownerId: ownerId);
        unawaited(cubit.load());
        return cubit;
      },
      child: RepositoryProvider(
        create: (context) => SaleCubits(
          saleRepository: repository,
          propertyRepository: context.read<PropertyRepository>(),
          valuationRepository: context.read<ValuationRepository>(),
          ownerId: ownerId,
          context: () {
            final state = context.read<SellerPropertiesCubit>().state;
            return (state.properties, state.lots);
          },
          onSaleChanged: () => unawaited(context.read<SalesCubit>().load()),
          userAgent:
              '${Platform.operatingSystem} '
              '${Platform.operatingSystemVersion}',
        ),
        dispose: (cubits) => unawaited(cubits.close()),
        child: child,
      ),
    );
  }
}

/// Builds with the seller's sales, rebuilt when they change; with null
/// when sales are not available.
class SalesBuilder extends StatelessWidget {
  const new({required this.builder, super.key});

  final Widget Function(BuildContext context, List<Sale>? sales) builder;

  @override
  Widget build(BuildContext context) {
    final cubit = salesCubitOf(context);
    if (cubit == null) return builder(context, null);
    return BlocBuilder<SalesCubit, SalesState>(
      bloc: cubit,
      builder: (context, state) => builder(context, state.sales),
    );
  }
}
