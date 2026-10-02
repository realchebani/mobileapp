import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/dashboard/dashboard_page.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/view/seller_home_page.dart';

/// Root of the "Mon bien" tab: start / resume the audit while the dossier
/// is a draft ([SellerHomePage]), the V9 [DashboardPage] once it is sent.
class MyPropertyPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final isLocked = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isLocked,
    );
    return isLocked ? const DashboardPage() : const SellerHomePage();
  }
}
