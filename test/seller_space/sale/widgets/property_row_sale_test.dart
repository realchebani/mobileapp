import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/my_properties/widgets/property_row.dart';
import 'package:mobileapp/seller_space/sale/sale.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../helpers/helpers.dart';
import '../../fixtures.dart';
import '../sale_helpers.dart';

void main() {
  testWidgets('"Mes biens" shows where the sale stands', (tester) async {
    Future<void> pump(Property property, List<Sale> sales) => tester.pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<SellerPropertiesCubit>.value(
            value: propertiesCubit(properties: [property]),
          ),
          BlocProvider<SalesCubit>.value(value: salesCubit(sales)),
        ],
        child: PropertyRow(property: property),
      ),
    );

    await pump(certifiedProperty, const [testSale]);
    expect(find.text('L’Essentiel · Mandat à signer'), findsOneWidget);
    const member = Property(
      id: 'other',
      ownerId: 'user-id',
      status: PropertyStatus.certified,
      lotId: 'lot',
    );
    await pump(member, const [
      Sale(
        id: 's',
        lotId: 'lot',
        formula: SaleFormula.expert,
        stage: SaleStage.planChosen,
      ),
    ]);
    expect(find.text('L’Expert · Mandat à signer'), findsOneWidget);
    await pump(member, const []);
    expect(find.text('Certifié'), findsWidgets);
  });
}
