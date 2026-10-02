import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';

void main() {
  late NotificationRepository repository;
  final readAt = DateTime(2026, 10);
  final read = testNotification.markedRead(readAt);

  setUp(() => repository = MockNotificationRepository());

  NotificationsCubit build() => NotificationsCubit(
    notificationRepository: repository,
    userId: 'user-id',
    timeout: const Duration(seconds: 1),
  );

  test('initial state', () {
    final cubit = NotificationsCubit(
      notificationRepository: repository,
      userId: 'user-id',
    );
    expect(cubit.state, const NotificationsState());
    expect(cubit.state.unreadCount, 0);
  });

  group('load', () {
    blocTest<NotificationsCubit, NotificationsState>(
      'loads the notifications of the user',
      setUp: () =>
          when(() => repository.getNotifications(any()))
              .thenAnswer((_) async => [testNotification]),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [
        const NotificationsState(status: NotificationsStatus.loading),
        NotificationsState(
          status: NotificationsStatus.success,
          notifications: [testNotification],
        ),
      ],
      verify: (cubit) {
        expect(cubit.state.unreadCount, 1);
        verify(() => repository.getNotifications('user-id')).called(1);
      },
    );

    blocTest<NotificationsCubit, NotificationsState>(
      'fails',
      setUp: () =>
          when(() => repository.getNotifications(any()))
              .thenThrow(const NotificationFailure()),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => const [
        NotificationsState(status: NotificationsStatus.loading),
        NotificationsState(status: NotificationsStatus.failure),
      ],
      errors: () => [isA<NotificationFailure>()],
    );

    blocTest<NotificationsCubit, NotificationsState>(
      'ignores a load while loading',
      build: build,
      seed: () => const NotificationsState(status: NotificationsStatus.loading),
      act: (cubit) => cubit.load(),
      expect: () => const <NotificationsState>[],
    );

    test('ignores answers arriving after close', () async {
      final success = Completer<List<AppNotification>>();
      final failure = Completer<List<AppNotification>>();
      var calls = 0;
      when(() => repository.getNotifications(any()))
          .thenAnswer((_) => calls++ == 0 ? success.future : failure.future);
      final first = build();
      final loadingFirst = first.load();
      await first.close();
      success.complete([testNotification]);
      await loadingFirst;
      expect(first.state.status, NotificationsStatus.loading);

      final second = build();
      final loadingSecond = second.load();
      await second.close();
      failure.completeError(const NotificationFailure());
      await loadingSecond;
      expect(second.state.status, NotificationsStatus.loading);
    });
  });

  group('markAllRead', () {
    blocTest<NotificationsCubit, NotificationsState>(
      'marks the unread notifications read',
      setUp: () =>
          when(() => repository.markRead(any()))
              .thenAnswer((_) async => readAt),
      build: build,
      seed: () => NotificationsState(
        status: NotificationsStatus.success,
        notifications: [testNotification],
      ),
      act: (cubit) => cubit.markAllRead(),
      expect: () => [
        NotificationsState(
          status: NotificationsStatus.success,
          notifications: [read],
        ),
      ],
      verify: (_) =>
          verify(() => repository.markRead(['notification-id'])).called(1),
    );

    blocTest<NotificationsCubit, NotificationsState>(
      'does nothing when everything is read',
      build: build,
      seed: () => NotificationsState(notifications: [read]),
      act: (cubit) => cubit.markAllRead(),
      expect: () => const <NotificationsState>[],
      verify: (_) => verifyNever(() => repository.markRead(any())),
    );

    blocTest<NotificationsCubit, NotificationsState>(
      'keeps them unread on failure',
      setUp: () =>
          when(() => repository.markRead(any()))
              .thenThrow(const NotificationFailure()),
      build: build,
      seed: () => NotificationsState(notifications: [testNotification]),
      act: (cubit) => cubit.markAllRead(),
      expect: () => const <NotificationsState>[],
      errors: () => [isA<NotificationFailure>()],
    );

    test('ignores answers arriving after close', () async {
      final success = Completer<DateTime>();
      final failure = Completer<DateTime>();
      var calls = 0;
      when(() => repository.markRead(any()))
          .thenAnswer((_) => calls++ == 0 ? success.future : failure.future);
      final first = build()
        ..emit(NotificationsState(notifications: [testNotification]));
      final marking = first.markAllRead();
      await first.close();
      success.complete(readAt);
      await marking;
      expect(first.state.unreadCount, 1);

      final second = build()
        ..emit(NotificationsState(notifications: [testNotification]));
      final markingSecond = second.markAllRead();
      await second.close();
      failure.completeError(const NotificationFailure());
      await markingSecond;
      expect(second.state.unreadCount, 1);
    });
  });
}
