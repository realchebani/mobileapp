import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sale_repository/sale_repository.dart';

part 'notification_list_state.dart';

/// The full list of the user's notifications (EPIC-11, US-11.8), by pages
/// of [pageSize], newest first.
class NotificationListCubit extends Cubit<NotificationListState> {
  new({
    required this._notificationRepository,
    required this._userId,
    this._timeout = const Duration(seconds: 15),
  }) : super(const NotificationListState());

  /// The repository's page size.
  static const pageSize = 50;

  final NotificationRepository _notificationRepository;
  final String _userId;
  final Duration _timeout;

  /// Loads the first page (the current list stays shown).
  Future<void> load() async {
    emit(state.copyWith(status: NotificationListStatus.loading));
    try {
      final page = await _notificationRepository
          .getNotifications(_userId)
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        NotificationListState(
          status: NotificationListStatus.success,
          notifications: page,
          hasMore: page.length == pageSize,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: NotificationListStatus.failure));
    }
  }

  /// Loads the next page ("Voir plus").
  Future<void> loadMore() async {
    final last = state.notifications.lastOrNull;
    if (last == null || !state.hasMore || state.loadingMore) return;
    emit(state.copyWith(loadingMore: true, moreFailed: false));
    try {
      final page = await _notificationRepository
          .getNotifications(_userId, before: last.createdAt)
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          notifications: [...state.notifications, ...page],
          hasMore: page.length == pageSize,
          loadingMore: false,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(loadingMore: false, moreFailed: true));
    }
  }

  /// Marks every notification read (on failure, [NotificationListState.
  /// markAllFailed]).
  Future<void> markAllRead() async {
    emit(state.copyWith(markAllFailed: false));
    try {
      final at = await _notificationRepository
          .markAllRead(_userId)
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
      emit(state.copyWith(markAllFailed: true));
    }
  }

  /// Marks [notification] read (it is being opened); best effort.
  Future<void> markRead(AppNotification notification) async {
    if (notification.isRead) return;
    try {
      final at = await _notificationRepository
          .markRead([notification.id])
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          notifications: [
            for (final n in state.notifications)
              if (n.id == notification.id) n.markedRead(at) else n,
          ],
        ),
      );
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
    }
  }
}
