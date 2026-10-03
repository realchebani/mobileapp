import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/sale/sale.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';

class MockSaleCubit extends MockCubit<SaleState> implements SaleCubit;

class MockSalesCubit extends MockCubit<SalesState> implements SalesCubit;

class MockSaleCubits extends Mock implements SaleCubits;

const testSale = Sale(
  id: 'sale-id',
  ownerId: 'user-id',
  propertyId: 'property-id',
  formula: SaleFormula.essentiel,
  stage: SaleStage.planChosen,
  askingPriceEur: 525000,
);

final testMandate = Mandate(
  id: 'mandate-id',
  saleId: 'sale-id',
  formula: SaleFormula.essentiel,
  signedAt: DateTime(2026, 10, 3, 10),
  documentPath: 'user-id/sale-id/mandat-mandate-id.pdf',
);

const testOwners = [
  PropertyOwner(
    id: 'owner-1',
    propertyId: 'property-id',
    position: 1,
    profileId: 'user-id',
    firstName: 'Sophie',
    lastName: 'Durand',
  ),
  PropertyOwner(
    id: 'owner-2',
    propertyId: 'property-id',
    position: 2,
    firstName: 'Marc',
    lastName: 'Durand',
  ),
];

/// A loaded sale of [certifiedProperty] (identity document present).
SaleState saleState({
  Sale sale = testSale,
  Mandate? mandate,
  List<SaleRequest> requests = const [],
  bool verified = false,
  Set<DocumentKind> documents = const {DocumentKind.identityDocument},
  SaleAction? busy,
  SaleFailure? failure,
  List<Property> members = const [certifiedProperty],
}) => SaleState(
  status: SaleLoadStatus.ready,
  sale: sale,
  mandate: mandate,
  requests: requests,
  members: members,
  valuations: {'property-id': testValuation},
  owners: testOwners,
  identities: {
    'owner-1': verified ? DateTime(2026, 10, 2) : null,
    'owner-2': null,
  },
  documentKinds: documents,
  busy: busy,
  failure: failure,
);

/// A [MockSaleCubit] in [state] whose actions do nothing.
MockSaleCubit mockSaleCubit(SaleState state) {
  registerFallbackValue(SaleFormula.essentiel);
  registerFallbackValue(SaleRequestKind.premiumSetup);
  registerFallbackValue(<String, Object?>{});
  registerFallbackValue(Uint8List(0));
  registerFallbackValue(
    const SaleRequest(id: 'r', saleId: 's', kind: SaleRequestKind.diagnostics),
  );
  final cubit = MockSaleCubit();
  when(() => cubit.state).thenReturn(state);
  when(cubit.refresh).thenAnswer((_) async {});
  when(() => cubit.changeFormula(any())).thenAnswer((_) async {});
  when(
    () => cubit.signMandate(
      signaturePng: any(named: 'signaturePng'),
      accepted: any(named: 'accepted'),
    ),
  ).thenAnswer((_) async {});
  when(cubit.openMandate).thenAnswer((_) async {});
  when(
    () => cubit.requestService(
      any(),
      diagnostics: any(named: 'diagnostics'),
      preferredSlots: any(named: 'preferredSlots'),
    ),
  ).thenAnswer((_) async {});
  when(() => cubit.cancelRequest(any())).thenAnswer((_) async {});
  when(() => cubit.updateListing(any())).thenAnswer((_) async {});
  when(cubit.publish).thenAnswer((_) async {});
  when(cubit.unpublish).thenAnswer((_) async {});
  when(() => cubit.withdraw(reason: any(named: 'reason')))
      .thenAnswer((_) async {});
  return cubit;
}

/// A [ProfileCubit] mock of the signed-in seller `user-id`.
MockProfileCubit sellerProfileCubit() {
  final cubit = MockProfileCubit();
  when(() => cubit.state).thenReturn(
    const ProfileState(
      status: ProfileStatus.success,
      profile: Profile(id: 'user-id', firstName: 'Sophie'),
    ),
  );
  return cubit;
}

extension PumpSale on WidgetTester {
  /// Pumps a sale screen [widget] under [saleCubit], the seller's profile
  /// and repositories.
  Future<void> pumpSalePage(
    Widget widget, {
    required SaleCubit saleCubit,
    SaleRepository? saleRepository,
    PropertyRepository? propertyRepository,
    ValuationRepository? valuationRepository,
    GoRouter? goRouter,
    PhotoServices? photoServices,
  }) {
    return pumpApp(
      BlocProvider<SaleCubit>.value(value: saleCubit, child: widget),
      profileCubit: sellerProfileCubit(),
      saleRepository: saleRepository ?? MockSaleRepository(),
      propertyRepository: propertyRepository,
      valuationRepository: valuationRepository,
      goRouter: goRouter,
      photoServices: photoServices,
    );
  }

  /// Saves the screen as a PNG in the scratchpad (design review), when
  /// `SALE_SCREENSHOTS` is set.
  Future<void> screenshot(String name) async {
    const directory = String.fromEnvironment('SALE_SCREENSHOTS');
    if (directory.isEmpty) return;
    final view = binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    await runAsync(() async {
      final image = await layer.toImage(view.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$directory/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }
}

/// [SellerPropertiesCubit] mock with [properties] and [lots].
MockSellerPropertiesCubit propertiesCubit({
  List<Property> properties = const [certifiedProperty],
  List<PropertyLot> lots = const [],
}) {
  final cubit = MockSellerPropertiesCubit();
  when(() => cubit.state).thenReturn(
    SellerPropertiesState(
      status: SellerPropertiesStatus.success,
      properties: properties,
      lots: lots,
    ),
  );
  return cubit;
}

/// A [MockSalesCubit] with [sales].
MockSalesCubit salesCubit([List<Sale> sales = const []]) {
  final cubit = MockSalesCubit();
  when(() => cubit.state)
      .thenReturn(SalesState(status: SalesStatus.success, sales: sales));
  when(cubit.load).thenAnswer((_) async {});
  return cubit;
}

/// A 390 px wide surface tall enough for a whole sale screen.
void useTallSurface([double height = 3200]) {
  final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
    ..physicalSize = Size(390, height)
    ..devicePixelRatio = 1;
  addTearDown(view.reset);
}

/// A [MockGoRouter] whose navigation does nothing.
MockGoRouter saleRouter() {
  final router = MockGoRouter();
  when(() => router.go(any())).thenReturn(null);
  when(() => router.push<Object?>(any())).thenAnswer((_) async => null);
  when(router.canPop).thenReturn(true);
  when(router.pop).thenReturn(null);
  return router;
}
