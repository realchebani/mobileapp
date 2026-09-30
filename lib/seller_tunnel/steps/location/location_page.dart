import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/view/provisional_step_view.dart';

/// V2 · Adresse & cadastre (provisional until the screen is built).
class LocationPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProvisionalStepView(step: SellerTunnelStep.location);
  }
}
