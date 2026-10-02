import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/dashboard/dashboard_page.dart';
import 'package:mobileapp/seller_space/dashboard/widgets/lot_card.dart';
import 'package:mobileapp/seller_space/lot/models/lot_estimate.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/view/seller_home_page.dart';
import 'package:mobileapp/ui/ui.dart';

/// Home of a property (under its `PropertyRouteScope`): start / resume the
/// audit while it is a draft ([SellerHomePage]), the V9 [DashboardPage]
/// once it is sent. Below: the lot it belongs to, and "Ajouter un bien"
/// while it is the seller's only property (owner decision Q7).
class PropertyHomePage extends StatelessWidget {
  const new({this.showBack = false, super.key});

  /// Whether a back arrow leads to "Mes biens" (the page of one property
  /// among several).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final isLocked = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isLocked,
    );
    final onBack = showBack ? () => context.go(AppRoutes.seller) : null;
    const footer = PropertyHomeFooter();
    return isLocked
        ? DashboardPage(onBack: onBack, footer: footer)
        : SellerHomePage(onBack: onBack, footer: footer);
  }
}

/// The lot of the open property, and "Ajouter un bien" while it is the
/// seller's only property.
class PropertyHomeFooter extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final id = context.select<SellerTunnelCubit, String>(
      (cubit) => cubit.state.property!.id,
    );
    final state = context.watch<SellerPropertiesCubit>().state;
    final lot = state.lotById(state.propertyById(id)?.lotId);
    final showAdd = state.properties.length == 1 && state.canAddProperty;
    if (lot == null && !showAdd) return const SizedBox.shrink();
    final members = lot == null ? null : state.membersOf(lot.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.sm,
      children: [
        if (lot != null)
          LotCard(
            lot: lot,
            members: members!,
            title: l10n.propertyHomeLotTitle(
              lotName(l10n, lot, members.length),
            ),
            estimate: LotEstimate.of(
              members: members,
              parcels: state.parcels,
              mainPropertyId: lot.mainPropertyId,
            ),
            onPressed: () => context.go(AppRoutes.sellerLot(lot.id)),
          ),
        if (showAdd)
          ActionCard(
            icon: RealestyIcons.plus,
            title: l10n.propertyHomeAddTitle,
            subtitle: l10n.propertyHomeAddSubtitle,
            onPressed: () => context.push(AppRoutes.sellerNewProperty),
          ),
      ],
    );
  }
}
