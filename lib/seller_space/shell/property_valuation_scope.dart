import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/cubit/valuation_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Provides the [ValuationCubit] of the open property (under its
/// `PropertyRouteScope`) to [child] (V9, V9b): loaded when the property is,
/// or becomes, certified.
class PropertyValuationScope extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = ValuationCubit(
          valuationRepository: context.read<ValuationRepository>(),
        );
        final property = context.read<SellerTunnelCubit>().state.property;
        if (property?.status == PropertyStatus.certified) {
          unawaited(cubit.load(property!.id));
        }
        return cubit;
      },
      child: BlocListener<SellerTunnelCubit, SellerTunnelState>(
        listenWhen: (previous, current) =>
            previous.property?.status != current.property?.status &&
            current.property?.status == PropertyStatus.certified,
        listener: (context, state) =>
            context.read<ValuationCubit>().load(state.property!.id),
        child: child,
      ),
    );
  }
}
