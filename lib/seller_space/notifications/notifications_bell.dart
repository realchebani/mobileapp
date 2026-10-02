import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_space/notifications/notifications_sheet.dart';
import 'package:mobileapp/ui/ui.dart';

/// Bell of the seller space headers (V9, Mes biens): opens the
/// notifications, with a red dot while some are unread.
class NotificationsBell extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final unread = context.select<NotificationsCubit, int>(
      (cubit) => cubit.state.unreadCount,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        RealestyIconButton(
          icon: RealestyIcons.bell,
          semanticLabel: unread > 0
              ? l10n.notificationsButtonUnread(unread)
              : l10n.notificationsButton,
          onPressed: () => showNotificationsSheet(context),
        ),
        if (unread > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(child: UnreadDot(color: c.erreur)),
          ),
      ],
    );
  }
}

/// Small red dot of an unread notification (bell, "Mes biens" rows).
class UnreadDot extends StatelessWidget {
  const new({this.color, this.semanticLabel, super.key});

  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      label: semanticLabel,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color ?? c.erreur,
          shape: BoxShape.circle,
          border: Border.all(color: c.surface, width: 2),
        ),
      ),
    );
  }
}
