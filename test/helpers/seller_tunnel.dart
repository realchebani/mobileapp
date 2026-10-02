import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
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

/// Route of the tunnel screen [step] of [testProperty].
String auditRoute(SellerTunnelStep step) => step.routeFor(testProperty.id);

/// Route of the V4 voice audit of [testProperty].
final String voiceAuditRoute = AppRoutes.sellerPropertyAudit(
  testProperty.id,
  SellerTunnelStep.voiceAuditSegment,
);

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
  registerFallbackValue(<PendingResolution, List<String>>{});
  when(
    () =>
        cubit.saveStepAndContinue(any(), any(), resolve: any(named: 'resolve')),
  ).thenAnswer((_) async {});
  when(() => cubit.saveStep(any(), resolve: any(named: 'resolve')))
      .thenAnswer((_) async {});
  when(() => cubit.resolvePending(any())).thenAnswer((_) async {});
  return cubit;
}

/// [room] without its `field_sources` (they hold the time of the change).
Room withoutSources(Room room) =>
    Room.fromJson({...room.toJson()}..remove('field_sources'));

/// The kinds of the `field_sources` of [room], by column.
Map<String, String?> sourceKinds(Room room) => {
  for (final MapEntry(:key, :value) in room.fieldSources.entries)
    key: (value! as Map)['s'] as String?,
};

/// The patch a step saved with `saveStepAndContinue` (EPIC-16), without
/// its `field_sources` (they hold the time of the save); verifies one call.
Map<String, Object?> savedStepPatch(
  SellerTunnelCubit cubit,
  SellerTunnelStep step,
) {
  final patch =
      verify(
            () => cubit.saveStepAndContinue(
              step,
              captureAny(),
              resolve: any(named: 'resolve'),
            ),
          ).captured.single
          as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in patch.entries)
      if (key != PropertyColumns.fieldSources) key: value,
  };
}

/// No step was saved with `saveStepAndContinue`.
void verifyNoStepSaved(SellerTunnelCubit cubit) => verifyNever(
  () => cubit.saveStepAndContinue(any(), any(), resolve: any(named: 'resolve')),
);

/// A [MockSellerPropertiesCubit] with [properties] (and [lots]) loaded.
MockSellerPropertiesCubit mockSellerPropertiesCubit({
  List<Property> properties = const [testProperty],
  List<PropertyLot> lots = const [],
  Map<String, Set<String>> parcels = const {},
}) {
  final cubit = MockSellerPropertiesCubit();
  when(() => cubit.state).thenReturn(
    SellerPropertiesState(
      status: SellerPropertiesStatus.success,
      properties: properties,
      lots: lots,
      parcels: parcels,
    ),
  );
  when(cubit.load).thenAnswer((_) async {});
  when(cubit.refresh).thenAnswer((_) async {});
  return cubit;
}

/// A [MockSellerTunnelCubits] giving [cubit] for every property.
MockSellerTunnelCubits mockSellerTunnelCubits(SellerTunnelCubit cubit) {
  final cubits = MockSellerTunnelCubits();
  when(() => cubits.of(any())).thenReturn(cubit);
  when(() => cubits.forget(any())).thenAnswer((_) async {});
  return cubits;
}

extension PumpSellerTunnel on WidgetTester {
  /// Pumps a seller tunnel [widget] (e.g. a step page) under
  /// [sellerTunnelCubit] (default: [mockSellerTunnelCubit]) and the app
  /// mocks of [pumpApp].
  Future<void> pumpTunnelPage(
    Widget widget, {
    SellerTunnelCubit? sellerTunnelCubit,
    SellerPropertiesCubit? sellerPropertiesCubit,
    PropertyRepository? propertyRepository,
    GeoRepository? geoRepository,
    AppBloc? appBloc,
    GoRouter? goRouter,
    PhotoServices? photoServices,
  }) {
    // A step view reads its trace (EPIC-16), provided by its page: an
    // empty one (no notes, nothing pre-filled) unless the test gives one.
    final tunnel = BlocProvider<SellerTunnelCubit>.value(
      value: sellerTunnelCubit ?? mockSellerTunnelCubit(),
      child: BlocProvider<StepTraceCubit>(
        create: (_) => StepTraceCubit(const StepTraceState()),
        child: widget,
      ),
    );
    return pumpApp(
      sellerPropertiesCubit == null
          ? tunnel
          : BlocProvider<SellerPropertiesCubit>.value(
              value: sellerPropertiesCubit,
              child: tunnel,
            ),
      propertyRepository: propertyRepository,
      geoRepository: geoRepository,
      appBloc: appBloc,
      goRouter: goRouter,
      photoServices: photoServices,
    );
  }
}
