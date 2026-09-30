import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/view/provisional_step_view.dart';

/// V6 · Cadre de vie (provisional until the screen is built).
class LifestylePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProvisionalStepView(step: SellerTunnelStep.lifestyle);
  }
}
