import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/account/notifications/cubit/notification_list_cubit.dart';
import 'package:mobileapp/seller_space/account/widgets/account_screen.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_space/notifications/notifications_sheet.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Notifications (EPIC-11, US-11.8, not designed): every notification of
/// the user, grouped by date, with the property it is about; opening one
/// goes to its screen. In-app only: no push / e-mail settings.
class NotificationsPage extends StatelessWidget {
  const new({this.now, super.key});

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = NotificationListCubit(
          notificationRepository: context.read<NotificationRepository>(),
          userId: context.read<ProfileCubit>().state.profile?.id ?? '',
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: NotificationsView(now: now ?? DateTime.now),
    );
  }
}

/// When a notification was received, for its group.
enum NotificationAge { today, thisWeek, older }

/// The group of a notification created at [date], seen at [now].
NotificationAge notificationAge(DateTime date, DateTime now) {
  final local = date.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  if (!local.isBefore(today)) return NotificationAge.today;
  if (!local.isBefore(today.subtract(const Duration(days: 6)))) {
    return NotificationAge.thisWeek;
  }
  return NotificationAge.older;
}

class NotificationsView extends StatelessWidget {
  const new({required this.now, super.key});

  final DateTime Function() now;

  Future<void> _markAll(BuildContext context) async {
    final l10n = context.l10n;
    final appNotifications = context.read<NotificationsCubit?>();
    final cubit = context.read<NotificationListCubit>();
    await cubit.markAllRead();
    if (!context.mounted) return;
    if (!cubit.state.markAllFailed) {
      unawaited(appNotifications?.load());
    } else {
      showRealestySnackBar(
        context,
        l10n.notificationsPageMarkFailed,
        isError: true,
      );
    }
  }

  Future<void> _open(BuildContext context, AppNotification notification) async {
    final router = GoRouter.of(context);
    final appNotifications = context.read<NotificationsCubit?>();
    await context.read<NotificationListCubit>().markRead(notification);
    unawaited(appNotifications?.load());
    final route = notification.route;
    if (route != null) router.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<NotificationListCubit>().state;
    final properties =
        context.watch<SellerPropertiesCubit?>()?.state.properties ?? const [];
    final labels = properties.length < 2
        ? const <String, String>{}
        : {
            for (final property in properties)
              property.id: propertyShortLabel(l10n, property),
          };
    final List<Widget> children;
    if (state.notifications.isEmpty) {
      children = [
        switch (state.status) {
          NotificationListStatus.failure => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.md,
            children: [
              InlineBanner(message: l10n.notificationsError),
              RealestyButton(
                label: l10n.vaultRetry,
                variant: RealestyButtonVariant.secondary,
                onPressed: () => context.read<NotificationListCubit>().load(),
              ),
            ],
          ),
          NotificationListStatus.success => Padding(
            padding: const EdgeInsets.symmetric(vertical: RealestySpacing.xl),
            child: Text(
              l10n.notificationsEmpty,
              textAlign: TextAlign.center,
              style: RealestyTextStyles.body.copyWith(color: c.texteDiscret),
            ),
          ),
          NotificationListStatus.initial ||
          NotificationListStatus.loading => Padding(
            padding: const EdgeInsets.all(RealestySpacing.xl),
            child: Center(child: CircularProgressIndicator(color: c.vertTexte)),
          ),
        },
      ];
    } else {
      final at = now();
      children = [
        for (final age in NotificationAge.values)
          if (state.notifications
                  .where((n) => notificationAge(n.createdAt, at) == age)
                  .toList()
              case final group when group.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
              child: Semantics(
                header: true,
                child: Text(
                  switch (age) {
                    NotificationAge.today => l10n.notificationsPageToday,
                    NotificationAge.thisWeek => l10n.notificationsPageThisWeek,
                    NotificationAge.older => l10n.notificationsPageOlder,
                  }.toUpperCase(),
                  style: RealestyTextStyles.caption.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RealestySpacing.md,
              ),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(RealestyRadius.card),
                border: Border.all(color: c.bordureCarte),
              ),
              child: Column(
                children: [
                  for (final (index, notification) in group.indexed)
                    NotificationTile(
                      notification: notification,
                      propertyLabel: labels[notification.propertyId],
                      showDivider: index < group.length - 1,
                      onTap: () => _open(context, notification),
                    ),
                ],
              ),
            ),
            const SizedBox(height: RealestySpacing.lg),
          ],
        if (state.moreFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: RealestySpacing.sm),
            child: InlineBanner(message: l10n.notificationsError),
          ),
        if (state.hasMore)
          RealestyButton(
            label: l10n.notificationsPageMore,
            variant: RealestyButtonVariant.secondary,
            isLoading: state.loadingMore,
            onPressed: () => context.read<NotificationListCubit>().loadMore(),
          ),
      ];
    }
    return AccountScreen(
      title: l10n.notificationsTitle,
      trailing: state.unreadCount > 0
          ? RealestyButton(
              label: l10n.notificationsPageMarkAll,
              variant: RealestyButtonVariant.text,
              expand: false,
              height: 36,
              onPressed: () => _markAll(context),
            )
          : null,
      children: children,
    );
  }
}
