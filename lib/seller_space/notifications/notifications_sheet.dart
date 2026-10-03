import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Opens the notifications list (bell of V9) as a bottom sheet. They are
/// marked read when it closes; tapping one opens its screen.
///
/// With several properties, each title starts with the property it is
/// about ("Garage · Rue des Lilas · …").
Future<void> showNotificationsSheet(BuildContext context) async {
  final cubit = context.read<NotificationsCubit>();
  final router = GoRouter.of(context);
  final l10n = context.l10n;
  final properties =
      context.read<SellerPropertiesCubit?>()?.state.properties ?? const [];
  final labels = properties.length < 2
      ? const <String, String>{}
      : {
          for (final property in properties)
            property.id: propertyShortLabel(l10n, property),
        };
  unawaited(cubit.load());
  final route = await showModalBottomSheet<String>(
    context: context,
    // Above the tab bar.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.realestyColors.ivoire,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RealestyRadius.sheet),
      ),
    ),
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: NotificationsSheet(propertyLabels: labels),
    ),
  );
  await cubit.markAllRead();
  if (route != null) router.go(route);
}

/// The notifications, newest first; pops with the route of the tapped one.
class NotificationsSheet extends StatelessWidget {
  const new({this.propertyLabels = const {}, super.key});

  /// Short label of each property (by id), to prefix the titles.
  final Map<String, String> propertyLabels;

  /// Notifications shown (the latest); "Tout voir" opens the full list.
  static const sheetLimit = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<NotificationsCubit>().state;
    final latest = state.notifications.take(sheetLimit).toList();
    final Widget content;
    if (state.notifications.isNotEmpty) {
      content = Column(
        children: [
          for (final (index, notification) in latest.indexed)
            NotificationTile(
              notification: notification,
              propertyLabel: propertyLabels[notification.propertyId],
              showDivider: index < latest.length - 1,
              onTap: switch (notification.route) {
                final route? => () => Navigator.of(context).pop(route),
                null => null,
              },
            ),
        ],
      );
    } else if (state.status == NotificationsStatus.failure) {
      content = InlineBanner(message: l10n.notificationsError);
    } else if (state.status == NotificationsStatus.success) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: RealestySpacing.xl),
        child: Text(
          l10n.notificationsEmpty,
          textAlign: TextAlign.center,
          style: RealestyTextStyles.body.copyWith(color: c.texteDiscret),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(RealestySpacing.xl),
        child: Center(child: CircularProgressIndicator(color: c.vertTexte)),
      );
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          RealestySpacing.lg,
          RealestySpacing.gutter,
          RealestySpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.md,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.notificationsTitle,
                      style: RealestyTextStyles.title2.copyWith(color: c.encre),
                    ),
                  ),
                ),
                RealestyButton(
                  label: l10n.notificationsSeeAll,
                  variant: RealestyButtonVariant.text,
                  expand: false,
                  height: 36,
                  onPressed: () =>
                      Navigator.of(context).pop(AppRoutes.sellerNotifications),
                ),
                RealestyIconButton(
                  icon: RealestyIcons.close,
                  semanticLabel: MaterialLocalizations.of(context)
                      .closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            content,
          ],
        ),
      ),
    );
  }
}

/// A notification: icon, title (prefixed by its property), body, date and
/// an unread dot; [onTap] opens it.
class NotificationTile extends StatelessWidget {
  const new({
    required this.notification,
    required this.showDivider,
    this.propertyLabel,
    this.onTap,
    super.key,
  });

  final AppNotification notification;
  final String? propertyLabel;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final body = notification.body;
    final date = notification.createdAt;
    return RealestyPressable(
      onPressed: onTap,
      showDisabled: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: RealestySpacing.sm),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: c.bordureCarte))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: RealestySpacing.sm,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.vertTeinte,
                borderRadius: BorderRadius.circular(RealestyRadius.field),
              ),
              child: RealestyIcon(switch (notification.kind) {
                AppNotificationKind.valuationCertified => RealestyIcons.shield,
                AppNotificationKind.documentRejected ||
                AppNotificationKind.documentVerified => RealestyIcons.file,
                AppNotificationKind.mandateSigned => RealestyIcons.pen,
                AppNotificationKind.identityVerified => RealestyIcons.user,
                AppNotificationKind.listingPublished => RealestyIcons.home,
                AppNotificationKind.saleRequestUpdated =>
                  RealestyIcons.calendar,
                AppNotificationKind.reviewStarted ||
                AppNotificationKind.saleWithdrawn ||
                AppNotificationKind.other => RealestyIcons.bell,
              }, color: c.vertTexte),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    switch (propertyLabel) {
                      final label? => l10n.notificationsPropertyPrefix(
                        label,
                        notification.title,
                      ),
                      null => notification.title,
                    },
                    style: RealestyTextStyles.listTitle.copyWith(
                      color: c.encre,
                      fontWeight: notification.isRead
                          ? FontWeight.w600
                          : FontWeight.w700,
                    ),
                  ),
                  if (body != null)
                    Text(
                      body,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.texteDiscret,
                      ),
                    ),
                  Text(
                    l10n.notificationsDate(
                      fullDate(date),
                      timeOfDay(l10n, date),
                    ),
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      fontSize: 12,
                      color: c.texteDiscret,
                    ),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Semantics(
                label: l10n.notificationsUnread,
                child: Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: c.vert,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
