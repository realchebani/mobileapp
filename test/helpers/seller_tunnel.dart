import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import 'mocks.dart';
import 'pump_app.dart';

/// A loaded draft, for seller tunnel tests.
const testProperty = Property(id: 'property-id', ownerId: 'user-id');

/// A [MockSellerTunnelCubit] in [state] (a loaded [testProperty] by
/// default), whose save methods do nothing.
MockSellerTunnelCubit mockSellerTunnelCubit([
  SellerTunnelState state = const SellerTunnelState(
    status: SellerTunnelStatus.success,
    property: testProperty,
  ),
]) {
  registerFallbackValue(SellerTunnelStep.owners);
  registerFallbackValue(<String, Object?>{});
  final cubit = MockSellerTunnelCubit();
  when(() => cubit.state).thenReturn(state);
  when(cubit.load).thenAnswer((_) async {});
  when(cubit.retry).thenAnswer((_) async {});
  when(() => cubit.save(any())).thenAnswer((_) async {});
  when(() => cubit.saveAndContinue(any(), any())).thenAnswer((_) async {});
  when(() => cubit.saveAndContinue(any())).thenAnswer((_) async {});
  return cubit;
}

extension PumpSellerTunnel on WidgetTester {
  /// Pumps a seller tunnel [widget] (e.g. a step page) under
  /// [sellerTunnelCubit] (default: [mockSellerTunnelCubit]) and the app
  /// mocks of [pumpApp].
  Future<void> pumpTunnelPage(
    Widget widget, {
    SellerTunnelCubit? sellerTunnelCubit,
    PropertyRepository? propertyRepository,
    AppBloc? appBloc,
    GoRouter? goRouter,
  }) {
    return pumpApp(
      BlocProvider<SellerTunnelCubit>.value(
        value: sellerTunnelCubit ?? mockSellerTunnelCubit(),
        child: widget,
      ),
      propertyRepository: propertyRepository,
      appBloc: appBloc,
      goRouter: goRouter,
    );
  }
}
