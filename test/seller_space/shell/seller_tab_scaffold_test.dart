import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';
import '../pump_seller_space.dart';

void main() {
  group(SellerTabView, () {
    testWidgets('shows the tabs and the unread dot', (tester) async {
      final tapped = <int>[];
      await tester.pumpSellerSpacePage(
        SellerTabView(
          currentIndex: 0,
          onTabSelected: tapped.add,
          child: const Text('content'),
        ),
        notificationsCubit: mockNotificationsCubit(
          NotificationsState(notifications: [testNotification]),
        ),
      );
      expect(find.text('content'), findsOneWidget);
      for (final label in ['Mon bien', 'Visites', 'Coffre-fort', 'Compte']) {
        expect(find.text(label), findsOneWidget);
      }
      final bar = tester.widget<RealestyTabBar>(find.byType(RealestyTabBar));
      expect(bar.tabs.first.badge, isTrue);
      await tester.tap(find.text('Compte'));
      expect(tapped, [3]);
    });
  });

  group(SellerSpaceProviders, () {
    late NotificationRepository notificationRepository;
    late MockProfileCubit profileCubit;

    setUp(() {
      notificationRepository = MockNotificationRepository();
      when(() => notificationRepository.getNotifications(any()))
          .thenAnswer((_) async => [testNotification]);
      profileCubit = MockProfileCubit();
      when(() => profileCubit.state)
          .thenReturn(const ProfileState(profile: Profile(id: 'user-id')));
    });

    Future<void> pump(WidgetTester tester) => tester.pumpApp(
      SellerSpaceProviders(
        child: Builder(
          builder: (context) =>
              Text('${context.watch<NotificationsCubit>().state.unreadCount}'),
        ),
      ),
      notificationRepository: notificationRepository,
      profileCubit: profileCubit,
    );

    testWidgets('loads the notifications of the user', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      verify(() => notificationRepository.getNotifications('user-id'))
          .called(1);
    });

    testWidgets('works without a profile', (tester) async {
      when(() => profileCubit.state).thenReturn(const ProfileState());
      await pump(tester);
      await tester.pumpAndSettle();
      verify(() => notificationRepository.getNotifications('')).called(1);
    });
  });

  group(PropertyValuationScope, () {
    late ValuationRepository valuationRepository;

    setUp(() {
      valuationRepository = MockValuationRepository();
      when(() => valuationRepository.getLatestValuation(any()))
          .thenAnswer((_) async => testValuation);
    });

    Future<void> pump(
      WidgetTester tester,
      SellerTunnelCubit tunnel,
    ) => tester.pumpApp(
      BlocProvider<SellerTunnelCubit>.value(
        value: tunnel,
        child: PropertyValuationScope(
          child: Builder(
            builder: (context) => Text(
              '${context.watch<ValuationCubit>().state.valuation?.valueEur}',
            ),
          ),
        ),
      ),
      valuationRepository: valuationRepository,
    );

    testWidgets('loads the valuation of a certified dossier', (tester) async {
      await pump(tester, mockSellerTunnelCubit(certifiedState));
      await tester.pumpAndSettle();
      expect(find.text('525000'), findsOneWidget);
    });

    testWidgets('loads it once the dossier becomes certified', (tester) async {
      const submitted = SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'property-id',
          ownerId: 'user-id',
          status: PropertyStatus.submitted,
        ),
      );
      final tunnel = mockSellerTunnelCubit(submitted);
      final states = StreamController<SellerTunnelState>();
      addTearDown(states.close);
      whenListen(tunnel, states.stream, initialState: submitted);
      await pump(tester, tunnel);
      await tester.pumpAndSettle();
      expect(find.text('null'), findsOneWidget);
      verifyNever(() => valuationRepository.getLatestValuation(any()));

      states.add(certifiedState);
      await tester.pumpAndSettle();
      expect(find.text('525000'), findsOneWidget);
    });
  });
}
