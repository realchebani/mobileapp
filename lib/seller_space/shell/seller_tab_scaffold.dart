import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_space/cubit/valuation_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Seller space with its tab bar (Mon bien · Visites · Coffre-fort ·
/// Compte), built by the `StatefulShellRoute` of `/vendeur`: each tab keeps
/// its own navigation stack.
///
/// Provides the [ValuationCubit] (loaded once the dossier is certified)
/// and the [NotificationsCubit] to the tabs.
class SellerTabScaffold extends StatelessWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return SellerSpaceProviders(
      child: SellerTabView(
        currentIndex: navigationShell.currentIndex,
        // Tapping the current tab goes back to its root.
        onTabSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        child: navigationShell,
      ),
    );
  }
}

/// Creates the seller space cubits: the valuation of the dossier (loaded
/// when it is, or becomes, certified) and the user's notifications.
class SellerSpaceProviders extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
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
        ),
        BlocProvider(
          create: (context) {
            final cubit = NotificationsCubit(
              notificationRepository: context.read<NotificationRepository>(),
              userId: context.read<ProfileCubit>().state.profile?.id ?? '',
            );
            unawaited(cubit.load());
            return cubit;
          },
        ),
      ],
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

/// The tab bar under [child]; the "Mon bien" tab shows a dot while there
/// are unread notifications.
class SellerTabView extends StatelessWidget {
  const new({
    required this.currentIndex,
    required this.onTabSelected,
    required this.child,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unread = context.select<NotificationsCubit, int>(
      (cubit) => cubit.state.unreadCount,
    );
    return Scaffold(
      backgroundColor: context.realestyColors.ivoire,
      body: child,
      bottomNavigationBar: RealestyTabBar(
        semanticLabel: l10n.tabBarLabel,
        currentIndex: currentIndex,
        onTap: onTabSelected,
        tabs: [
          RealestyTab(
            icon: RealestyIcons.home,
            label: l10n.tabBarMyProperty,
            badge: unread > 0,
          ),
          RealestyTab(icon: RealestyIcons.calendar, label: l10n.tabBarVisits),
          RealestyTab(icon: RealestyIcons.vault, label: l10n.tabBarVault),
          RealestyTab(icon: RealestyIcons.user, label: l10n.tabBarAccount),
        ],
      ),
    );
  }
}
