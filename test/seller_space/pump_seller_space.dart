import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../helpers/helpers.dart';
import 'fixtures.dart';

/// A [MockValuationCubit] in [state].
MockValuationCubit mockValuationCubit([
  ValuationState state = const ValuationState(),
]) {
  final cubit = MockValuationCubit();
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.load(any())).thenAnswer((_) async {});
  return cubit;
}

/// A [MockNotificationsCubit] in [state].
MockNotificationsCubit mockNotificationsCubit([
  NotificationsState state = const NotificationsState(),
]) {
  final cubit = MockNotificationsCubit();
  when(() => cubit.state).thenReturn(state);
  when(cubit.load).thenAnswer((_) async {});
  when(cubit.markAllRead).thenAnswer((_) async {});
  return cubit;
}

/// The loaded certified dossier with rooms.
const certifiedState = SellerTunnelState(
  status: SellerTunnelStatus.success,
  property: certifiedProperty,
  rooms: testRooms,
);

extension PumpSellerSpace on WidgetTester {
  /// Pumps a seller space [widget] under the tunnel, valuation and
  /// notifications cubits (mocks by default: a certified dossier).
  Future<void> pumpSellerSpacePage(
    Widget widget, {
    SellerTunnelCubit? sellerTunnelCubit,
    ValuationCubit? valuationCubit,
    NotificationsCubit? notificationsCubit,
    ValuationRepository? valuationRepository,
    ProfileCubit? profileCubit,
    AppBloc? appBloc,
    GoRouter? goRouter,
  }) {
    return pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<SellerTunnelCubit>.value(
            value: sellerTunnelCubit ?? mockSellerTunnelCubit(certifiedState),
          ),
          BlocProvider<ValuationCubit>.value(
            value: valuationCubit ?? mockValuationCubit(),
          ),
          BlocProvider<NotificationsCubit>.value(
            value: notificationsCubit ?? mockNotificationsCubit(),
          ),
        ],
        // The tab scaffold of the app (snackbars need a Scaffold).
        child: Scaffold(body: widget),
      ),
      valuationRepository: valuationRepository,
      profileCubit: profileCubit,
      appBloc: appBloc,
      goRouter: goRouter,
    );
  }
}
