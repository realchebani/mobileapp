import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Opens the notifications list (bell of V9) as a bottom sheet. They are
/// marked read when it closes; tapping one opens its screen.
Future<void> showNotificationsSheet(BuildContext context) async {
  final cubit = context.read<NotificationsCubit>();
  final router = GoRouter.of(context);
  unawaited(cubit.load());
  final route = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.realestyColors.ivoire,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RealestyRadius.sheet),
      ),
    ),
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const NotificationsSheet()),
  );
  await cubit.markAllRead();
  if (route != null) router.go(route);
}

/// The notifications, newest first; pops with the route of the tapped one.
class NotificationsSheet extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<NotificationsCubit>().state;
    final Widget content;
    if (state.notifications.isNotEmpty) {
      content = Column(
        children: [
          for (final (index, notification) in state.notifications.indexed)
            _NotificationTile(
              notification: notification,
              showDivider: index < state.notifications.length - 1,
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

class _NotificationTile extends StatelessWidget {
  const new({required this.notification, required this.showDivider});

  final AppNotification notification;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final body = notification.body;
    final route = notification.route;
    final date = notification.createdAt;
    return RealestyPressable(
      onPressed: route == null ? null : () => Navigator.of(context).pop(route),
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
              child: RealestyIcon(
                notification.kind == AppNotificationKind.valuationCertified
                    ? RealestyIcons.shield
                    : RealestyIcons.bell,
                color: c.vertTexte,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    notification.title,
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
