import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';
import '../pump_seller_space.dart';

void main() {
  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  Future<MockNotificationsCubit> open(
    WidgetTester tester,
    NotificationsState state, {
    SellerPropertiesCubit? sellerPropertiesCubit,
  }) async {
    final cubit = mockNotificationsCubit(state);
    await tester.pumpSellerSpacePage(
      sellerPropertiesCubit: sellerPropertiesCubit,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showNotificationsSheet(context),
          child: const Text('open'),
        ),
      ),
      notificationsCubit: cubit,
      goRouter: goRouter,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return cubit;
  }

  group('showNotificationsSheet', () {
    testWidgets('names the property of each notification', (tester) async {
      await open(
        tester,
        NotificationsState(
          status: NotificationsStatus.success,
          notifications: [
            AppNotification(
              id: 'n',
              kind: AppNotificationKind.valuationCertified,
              title: 'Disponible',
              propertyId: 'garage',
              createdAt: DateTime(2026, 9, 24),
            ),
          ],
        ),
        sellerPropertiesCubit: mockSellerPropertiesCubit(
          properties: const [
            testProperty,
            Property(
              id: 'garage',
              ownerId: 'user-id',
              propertyType: PropertyType.parking,
            ),
          ],
        ),
      );
      expect(find.text('Garage / parking · Disponible'), findsOneWidget);
    });

    testWidgets('opens the screen of a notification and marks them read', (
      tester,
    ) async {
      final cubit = await open(
        tester,
        NotificationsState(
          status: NotificationsStatus.success,
          notifications: [
            testNotification,
            AppNotification(
              id: 'other',
              kind: AppNotificationKind.reviewStarted,
              title: 'Un expert analyse votre dossier',
              createdAt: DateTime(2026, 9, 24),
              readAt: DateTime(2026, 9, 24),
            ),
          ],
        ),
      );
      verify(cubit.load).called(1);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Le 25/09/2026 à 10 h 05'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Non lue')), findsOneWidget);

      // Without a route, a notification is not a link.
      await tester.tap(find.text('Un expert analyse votre dossier'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);

      await tester.tap(find.text(testNotification.title));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsNothing);
      verify(cubit.markAllRead).called(1);
      verify(() => goRouter.go('/vendeur/rapport')).called(1);
    });

    testWidgets('shows the 10 latest and opens the full list', (tester) async {
      await open(
        tester,
        NotificationsState(
          status: NotificationsStatus.success,
          notifications: [
            for (var i = 0; i < 12; i++)
              AppNotification(
                id: 'n$i',
                kind: switch (i % 3) {
                  0 => AppNotificationKind.documentRejected,
                  1 => AppNotificationKind.documentVerified,
                  _ => AppNotificationKind.other,
                },
                title: 'Notification $i',
                createdAt: DateTime(2026, 9, 24),
              ),
          ],
        ),
      );
      expect(find.text('Notification 9'), findsOneWidget);
      expect(find.text('Notification 10'), findsNothing);
      await tester.tap(find.text('Tout voir'));
      await tester.pumpAndSettle();
      verify(() => goRouter.go(AppRoutes.sellerNotifications)).called(1);
    });

    testWidgets('closes without navigating', (tester) async {
      final cubit = await open(
        tester,
        const NotificationsState(status: NotificationsStatus.success),
      );
      expect(find.text('Aucune notification pour le moment.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      verify(cubit.markAllRead).called(1);
      verifyNever(() => goRouter.go(any()));
    });

    testWidgets('shows the loading and failure states', (tester) async {
      await open(
        tester,
        const NotificationsState(status: NotificationsStatus.failure),
      );
      expect(
        find.text('Impossible de charger vos notifications.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a spinner while loading', (tester) async {
      final cubit = mockNotificationsCubit(
        const NotificationsState(status: NotificationsStatus.loading),
      );
      await tester.pumpSellerSpacePage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNotificationsSheet(context),
            child: const Text('open'),
          ),
        ),
        notificationsCubit: cubit,
        goRouter: goRouter,
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
