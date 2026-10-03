import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../helpers/helpers.dart';
import '../../pump_seller_space.dart';

void main() {
  final now = DateTime(2026, 10, 3, 12);
  late MockNotificationRepository repository;
  late MockGoRouter router;
  late MockProfileCubit profileCubit;
  late MockNotificationsCubit appNotifications;

  AppNotification at(String id, DateTime date, {String? route}) =>
      AppNotification(
        id: id,
        kind: AppNotificationKind.documentRejected,
        title: 'Titre $id',
        propertyId: 'garage',
        route: route,
        createdAt: date,
      );

  void pages(Future<List<AppNotification>> Function(DateTime? before) answer) =>
      when(
        () => repository.getNotifications(
          'user-id',
          before: any(named: 'before'),
        ),
      ).thenAnswer(
        (invocation) => answer(invocation.namedArguments[#before] as DateTime?),
      );

  setUpAll(loadRealestyFonts);

  setUp(() {
    repository = MockNotificationRepository();
    registerFallbackValue(<String>[]);
    router = MockGoRouter();
    when(() => router.go(any())).thenReturn(null);
    when(() => router.canPop()).thenReturn(true);
    when(router.pop).thenReturn(null);
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(
      const ProfileState(
        status: ProfileStatus.success,
        profile: Profile(id: 'user-id'),
      ),
    );
    appNotifications = mockNotificationsCubit();
  });

  Future<void> pump(WidgetTester tester) async {
    usePhoneSurface();
    await tester.pumpSellerSpacePage(
      RepositoryProvider<NotificationRepository>.value(
        value: repository,
        child: NotificationsPage(now: () => now),
      ),
      sellerPropertiesCubit: mockSellerPropertiesCubit(
        properties: const [
          Property(id: 'property-id', ownerId: 'user-id'),
          Property(
            id: 'garage',
            ownerId: 'user-id',
            propertyType: PropertyType.parking,
          ),
        ],
      ),
      notificationsCubit: appNotifications,
      profileCubit: profileCubit,
      goRouter: router,
    );
    await tester.pumpAndSettle();
  }

  group(NotificationsPage, () {
    testWidgets('groups the notifications, opens one, marks all read', (
      tester,
    ) async {
      pages(
        (before) async => before == null
            ? [
                at('today', DateTime(2026, 10, 3, 9), route: '/vendeur'),
                at('week', DateTime(2026, 9, 30)),
                at('old', DateTime(2026, 9)),
                for (var i = 0; i < 47; i++) at('more$i', DateTime(2026, 8)),
              ]
            : [at('older', DateTime(2026, 7))],
      );
      when(() => repository.markRead(any())).thenAnswer((_) async => now);
      when(() => repository.markAllRead('user-id'))
          .thenAnswer((_) async => now);
      await pump(tester);
      expect(find.text('AUJOURD’HUI'), findsOneWidget);
      expect(find.text('CETTE SEMAINE'), findsOneWidget);
      expect(find.text('PLUS ANCIEN'), findsOneWidget);
      expect(find.text('Garage / parking · Titre today'), findsOneWidget);

      await tester.tap(find.text('Garage / parking · Titre today'));
      await tester.pumpAndSettle();
      verify(() => repository.markRead(['today'])).called(1);
      verify(() => router.go('/vendeur')).called(1);
      verify(appNotifications.load).called(1);

      await tester.tap(find.text('Garage / parking · Titre week'));
      await tester.pumpAndSettle();
      verifyNever(() => router.go(any(that: isNot('/vendeur'))));

      await tester.tap(find.text('Tout marquer comme lu'));
      await tester.pumpAndSettle();
      verify(() => repository.markAllRead('user-id')).called(1);
      expect(find.text('Tout marquer comme lu'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Voir plus'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Voir plus'));
      await tester.pumpAndSettle();
      expect(find.text('Voir plus'), findsNothing);
    });

    testWidgets('a failed "mark all read" is reported', (tester) async {
      pages((_) async => [at('a', DateTime(2026, 10, 3))]);
      when(() => repository.markAllRead('user-id'))
          .thenThrow(const NotificationFailure());
      await pump(tester);
      await tester.tap(find.text('Tout marquer comme lu'));
      await tester.pumpAndSettle();
      expect(
        find.text('Les notifications n’ont pas pu être marquées comme lues.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed next page is reported', (tester) async {
      pages(
        (before) async => before == null
            ? [for (var i = 0; i < 50; i++) at('n$i', DateTime(2026, 8))]
            : throw const NotificationFailure(),
      );
      await pump(tester);
      await tester.scrollUntilVisible(
        find.text('Voir plus'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Voir plus'));
      await tester.pumpAndSettle();
      expect(
        find.text('Impossible de charger vos notifications.'),
        findsOneWidget,
      );
    });

    testWidgets('empty, failure and retry', (tester) async {
      pages((_) => Future.error(const NotificationFailure()));
      await pump(tester);
      expect(
        find.text('Impossible de charger vos notifications.'),
        findsOneWidget,
      );
      pages((_) async => []);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune notification pour le moment.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(router.pop).called(1);
    });

    testWidgets('a spinner while loading', (tester) async {
      pages((_) => Future.delayed(const Duration(seconds: 1), () => []));
      usePhoneSurface();
      await tester.pumpSellerSpacePage(
        RepositoryProvider<NotificationRepository>.value(
          value: repository,
          child: const NotificationsPage(),
        ),
        profileCubit: profileCubit,
        goRouter: router,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });

  test('ages', () {
    expect(notificationAge(DateTime(2026, 10, 3), now), NotificationAge.today);
    expect(
      notificationAge(DateTime(2026, 9, 27), now),
      NotificationAge.thisWeek,
    );
    expect(notificationAge(DateTime(2026, 9, 26), now), NotificationAge.older);
  });
}
