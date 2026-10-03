import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/account/notifications/cubit/notification_list_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../helpers/helpers.dart';

AppNotification notification(int i, {DateTime? readAt}) => AppNotification(
  id: 'n$i',
  kind: AppNotificationKind.reviewStarted,
  title: 'N$i',
  createdAt: DateTime(2026, 9, 30).subtract(Duration(hours: i)),
  readAt: readAt,
);

void main() {
  late MockNotificationRepository repository;
  final now = DateTime(2026, 10, 3);

  setUp(() {
    repository = MockNotificationRepository();
    registerFallbackValue(<String>[]);
  });

  /// [first] for the first page, [next] for the following ones.
  void pages(
    Future<List<AppNotification>> Function() first,
    Future<List<AppNotification>> Function() next,
  ) =>
      when(
        () => repository.getNotifications(
          'user-id',
          before: any(named: 'before'),
        ),
      ).thenAnswer(
        (invocation) =>
            invocation.namedArguments[#before] == null ? first() : next(),
      );

  List<AppNotification> full() => [
    for (var i = 0; i < NotificationListCubit.pageSize; i++) notification(i),
  ];

  NotificationListCubit build() => NotificationListCubit(
    notificationRepository: repository,
    userId: 'user-id',
    timeout: const Duration(milliseconds: 50),
  );

  group(NotificationListCubit, () {
    blocTest<NotificationListCubit, NotificationListState>(
      'loads a page, then the next one',
      setUp: () => pages(() async => full(), () async => [notification(60)]),
      build: build,
      act: (cubit) async {
        await cubit.load();
        await cubit.loadMore();
        await cubit.loadMore();
      },
      verify: (cubit) {
        expect(cubit.state.notifications, hasLength(51));
        expect(cubit.state.hasMore, isFalse);
        expect(cubit.state.unreadCount, 51);
      },
    );

    blocTest<NotificationListCubit, NotificationListState>(
      'reports failures',
      setUp: () {
        when(() => repository.getNotifications('user-id'))
            .thenThrow(const NotificationFailure());
      },
      build: build,
      act: (cubit) => cubit.load(),
      errors: () => [isA<NotificationFailure>()],
      verify: (cubit) =>
          expect(cubit.state.status, NotificationListStatus.failure),
    );

    test('a failed next page can be tried again', () async {
      pages(
        () async => full(),
        () => Future.error(const NotificationFailure()),
      );
      final cubit = build();
      await cubit.load();
      await cubit.loadMore();
      expect(cubit.state.moreFailed, isTrue);
      expect(cubit.state.hasMore, isTrue);
      await cubit.close();
    });

    test('marks all, or one, read', () async {
      when(() => repository.getNotifications('user-id'))
          .thenAnswer((_) async => [notification(1), notification(2)]);
      when(() => repository.markAllRead('user-id'))
          .thenAnswer((_) async => now);
      when(() => repository.markRead(any())).thenAnswer((_) async => now);
      final cubit = build();
      await cubit.load();
      await cubit.markRead(cubit.state.notifications.first);
      expect(cubit.state.unreadCount, 1);
      await cubit.markRead(cubit.state.notifications.first);
      verify(() => repository.markRead(['n1'])).called(1);
      await cubit.markAllRead();
      expect(cubit.state.markAllFailed, isFalse);
      expect(cubit.state.unreadCount, 0);
      when(() => repository.markAllRead('user-id'))
          .thenThrow(const NotificationFailure());
      await cubit.markAllRead();
      expect(cubit.state.markAllFailed, isTrue);
      when(() => repository.markRead(any()))
          .thenThrow(const NotificationFailure());
      await cubit.load();
      await cubit.markRead(notification(1));
      await cubit.close();
    });

    test('nothing happens once closed', () async {
      final gate = Completer<List<AppNotification>>();
      when(() => repository.getNotifications('user-id'))
          .thenAnswer((_) => gate.future);
      final cubit = build();
      final load = cubit.load();
      await cubit.close();
      gate.complete([]);
      await load;

      final failing = Completer<List<AppNotification>>();
      when(() => repository.getNotifications('user-id'))
          .thenAnswer((_) => failing.future);
      final second = build();
      final secondLoad = second.load();
      await second.close();
      failing.completeError(const NotificationFailure());
      await secondLoad;

      final more = build();
      expect(more.state.props, hasLength(6));
      await more.loadMore();
      await more.close();
    });

    test('a closed cubit ignores late answers of the other calls', () async {
      final page = Completer<List<AppNotification>>();
      final all = Completer<DateTime>();
      final one = Completer<DateTime>();
      pages(() async => full(), () => page.future);
      when(() => repository.markAllRead('user-id'))
          .thenAnswer((_) => all.future);
      when(() => repository.markRead(any())).thenAnswer((_) => one.future);
      final cubit = build();
      await cubit.load();
      final calls = [
        cubit.loadMore(),
        cubit.markAllRead(),
        cubit.markRead(cubit.state.notifications.first),
      ];
      await cubit.close();
      page.complete([]);
      all.complete(now);
      one.complete(now);
      await Future.wait(calls);

      // And their failures.
      final failing = build();
      pages(
        () async => full(),
        () => Future.error(const NotificationFailure()),
      );
      await failing.load();
      final more = failing.loadMore();
      await failing.close();
      await more;
    });
  });
}
