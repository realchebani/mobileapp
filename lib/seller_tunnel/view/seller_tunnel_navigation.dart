import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';

/// Navigation helpers of the seller tunnel, for step screens.
extension SellerTunnelNavigation on BuildContext {
  /// Opens the screen of [step].
  void goToTunnelStep(SellerTunnelStep step) => go(step.path);

  /// Back from [step]: the previous screen, or the seller space.
  void goBackFrom(SellerTunnelStep step) =>
      go(step.previous?.path ?? AppRoutes.seller);

  /// Leaves the tunnel for the seller space (answers are already saved).
  void leaveTunnel() => go(AppRoutes.seller);
}
