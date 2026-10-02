import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Seller space with its tab bar (Mon bien · Visites · Coffre-fort ·
/// Compte), built by the `StatefulShellRoute` of `/vendeur`: each tab keeps
/// its own navigation stack.
///
/// Provides the [NotificationsCubit] to the tabs.
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

/// Creates the seller space cubits shared by the tabs: the user's
/// notifications (the valuation of a property is provided with it, see
/// `PropertyValuationScope`).
class SellerSpaceProviders extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = NotificationsCubit(
          notificationRepository: context.read<NotificationRepository>(),
          userId: context.read<ProfileCubit>().state.profile?.id ?? '',
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: child,
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
