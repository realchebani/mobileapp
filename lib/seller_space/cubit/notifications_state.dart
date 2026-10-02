part of 'notifications_cubit.dart';

enum NotificationsStatus { initial, loading, success, failure }

final class NotificationsState extends Equatable {
  const new({
    this.status = NotificationsStatus.initial,
    this.notifications = const [],
  });

  final NotificationsStatus status;

  /// Newest first.
  final List<AppNotification> notifications;

  int get unreadCount =>
      notifications.where((notification) => !notification.isRead).length;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotification>? notifications,
  }) => NotificationsState(
    status: status ?? this.status,
    notifications: notifications ?? this.notifications,
  );

  @override
  List<Object?> get props => [status, notifications];
}
