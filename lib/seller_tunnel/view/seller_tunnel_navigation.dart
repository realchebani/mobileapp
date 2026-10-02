import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';

/// Navigation helpers of the seller tunnel, for the screens of a property
/// (under its [SellerTunnelCubit]).
extension SellerTunnelNavigation on BuildContext {
  String get _propertyId => read<SellerTunnelCubit>().state.property!.id;

  /// Opens the screen of [step] of the open property.
  void goToTunnelStep(SellerTunnelStep step) => go(step.routeFor(_propertyId));

  /// Back from [step]: the previous screen of this type of property, or the
  /// home of the property.
  void goBackFrom(SellerTunnelStep step) {
    final previous = read<SellerTunnelCubit>().state.profile.previousBefore(
      step,
    );
    if (previous == null) {
      leaveTunnel();
    } else {
      goToTunnelStep(previous);
    }
  }

  /// Leaves the tunnel for the home of the property (answers are already
  /// saved).
  void leaveTunnel() => go(propertyHomeLocation(_propertyId));

  /// Home of the property [propertyId]: the "Mon bien" tab itself when it
  /// is the seller's only property, its own page otherwise.
  String propertyHomeLocation(String propertyId) {
    final properties = read<SellerPropertiesCubit?>()?.state.properties;
    return properties == null || properties.length <= 1
        ? AppRoutes.seller
        : AppRoutes.sellerProperty(propertyId);
  }
}
