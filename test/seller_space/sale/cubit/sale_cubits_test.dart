import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubits.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../helpers/helpers.dart';
import '../../fixtures.dart';
import '../sale_helpers.dart';

void main() {
  test('one cubit per sale, loaded once; changes are told', () async {
    final sales = MockSaleRepository();
    final properties = MockPropertyRepository();
    final valuations = MockValuationRepository();
    var sale = testSale;
    when(() => sales.getSale('sale-id')).thenAnswer((_) async => sale);
    when(() => sales.getMandate(any())).thenAnswer((_) async => null);
    when(() => sales.getRequests(any())).thenAnswer((_) async => []);
    when(() => sales.getIdentityVerifications(any()))
        .thenAnswer((_) async => {});
    when(() => valuations.getLatestValuation(any()))
        .thenAnswer((_) async => testValuation);
    when(() => properties.getOwners(any())).thenAnswer((_) async => []);
    when(() => properties.getDocuments(any())).thenAnswer((_) async => []);
    var changes = 0;
    final cubits = SaleCubits(
      saleRepository: sales,
      propertyRepository: properties,
      valuationRepository: valuations,
      ownerId: 'user-id',
      context: () => (const [certifiedProperty], const []),
      onSaleChanged: () => changes++,
      userAgent: 'ios',
    );
    final cubit = cubits.of('sale-id');
    expect(cubits.of('sale-id'), same(cubit));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.sale, testSale);
    sale = const Sale(
      id: 'sale-id',
      propertyId: 'property-id',
      formula: SaleFormula.premium,
      stage: SaleStage.planChosen,
    );
    await cubit.refresh();
    expect(changes, 1);
    await cubits.close();
    expect(cubit.isClosed, isTrue);

    final quiet = SaleCubits(
      saleRepository: sales,
      propertyRepository: properties,
      valuationRepository: valuations,
      ownerId: 'user-id',
      context: () => (const [], const []),
    );
    await (quiet..of('sale-id')).close();
  });
}
