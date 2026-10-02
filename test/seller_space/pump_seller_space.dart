import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
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
  /// Pumps a seller space [widget] under the tunnel, properties, valuation
  /// and notifications cubits (mocks by default: a certified dossier, the
  /// seller's only property).
  Future<void> pumpSellerSpacePage(
    Widget widget, {
    SellerTunnelCubit? sellerTunnelCubit,
    SellerPropertiesCubit? sellerPropertiesCubit,
    ValuationCubit? valuationCubit,
    NotificationsCubit? notificationsCubit,
    ValuationRepository? valuationRepository,
    PropertyRepository? propertyRepository,
    ProfileCubit? profileCubit,
    AppBloc? appBloc,
    GoRouter? goRouter,
  }) {
    final tunnel = sellerTunnelCubit ?? mockSellerTunnelCubit(certifiedState);
    return pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<SellerTunnelCubit>.value(value: tunnel),
          BlocProvider<SellerPropertiesCubit>.value(
            value:
                sellerPropertiesCubit ??
                mockSellerPropertiesCubit(properties: [?tunnel.state.property]),
          ),
          RepositoryProvider<SellerTunnelCubits>.value(
            value: mockSellerTunnelCubits(tunnel),
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
      propertyRepository: propertyRepository,
      profileCubit: profileCubit,
      appBloc: appBloc,
      goRouter: goRouter,
    );
  }
}
