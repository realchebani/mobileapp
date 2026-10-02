import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sale_repository/sale_repository.dart';

part 'notifications_state.dart';

/// In-app notifications of the signed-in user (bell of V9, tab badge).
class NotificationsCubit extends Cubit<NotificationsState> {
  new({
    required this._notificationRepository,
    required this._userId,
    this._timeout = const Duration(seconds: 15),
  }) : super(const NotificationsState());

  final NotificationRepository _notificationRepository;
  final String _userId;
  final Duration _timeout;

  /// Loads the latest notifications (the current list stays shown).
  Future<void> load() async {
    if (state.status == NotificationsStatus.loading) return;
    emit(state.copyWith(status: NotificationsStatus.loading));
    try {
      final notifications = await _notificationRepository
          .getNotifications(_userId)
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        NotificationsState(
          status: NotificationsStatus.success,
          notifications: notifications,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: NotificationsStatus.failure));
    }
  }

  /// Marks every unread notification read (on failure they stay unread).
  Future<void> markAllRead() async {
    final unread = [
      for (final notification in state.notifications)
        if (!notification.isRead) notification.id,
    ];
    if (unread.isEmpty) return;
    try {
      final at = await _notificationRepository
          .markRead(unread)
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          notifications: [
            for (final notification in state.notifications)
              notification.markedRead(at),
          ],
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
    }
  }
}
