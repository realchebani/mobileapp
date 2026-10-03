part of 'notification_list_cubit.dart';

enum NotificationListStatus { initial, loading, success, failure }

final class NotificationListState extends Equatable {
  const new({
    this.status = NotificationListStatus.initial,
    this.notifications = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.moreFailed = false,
    this.markAllFailed = false,
  });

  final NotificationListStatus status;

  /// Newest first.
  final List<AppNotification> notifications;

  /// Whether older notifications may exist.
  final bool hasMore;
  final bool loadingMore;

  /// The last "Voir plus" failed.
  final bool moreFailed;

  /// The last "Tout marquer comme lu" failed.
  final bool markAllFailed;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  NotificationListState copyWith({
    NotificationListStatus? status,
    List<AppNotification>? notifications,
    bool? hasMore,
    bool? loadingMore,
    bool? moreFailed,
    bool? markAllFailed,
  }) => NotificationListState(
    status: status ?? this.status,
    notifications: notifications ?? this.notifications,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
    markAllFailed: markAllFailed ?? this.markAllFailed,
  );

  @override
  List<Object?> get props => [
    status,
    notifications,
    hasMore,
    loadingMore,
    moreFailed,
    markAllFailed,
  ];
}
