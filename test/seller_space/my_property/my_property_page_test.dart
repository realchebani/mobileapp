import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';
import '../pump_seller_space.dart';

void main() {
  group(MyPropertyPage, () {
    testWidgets('one draft: start or resume the audit', (tester) async {
      await tester.pumpSellerSpacePage(
        const MyPropertyPage(),
        sellerTunnelCubit: mockSellerTunnelCubit(),
      );
      expect(find.byType(SellerHomePage), findsOneWidget);
      // The only property: "Ajouter un bien" at the bottom.
      expect(find.text('Ajouter un bien'), findsOneWidget);
    });

    testWidgets('one sent property: the dashboard', (tester) async {
      await tester.pumpSellerSpacePage(const MyPropertyPage());
      expect(find.byType(DashboardPage), findsOneWidget);
    });

    testWidgets('several properties: "Mes biens"', (tester) async {
      await tester.pumpSellerSpacePage(
        const MyPropertyPage(),
        sellerPropertiesCubit: mockSellerPropertiesCubit(
          properties: const [
            testProperty,
            Property(id: 'garage', ownerId: 'user-id'),
          ],
        ),
      );
      expect(find.byType(MyPropertiesPage), findsOneWidget);
    });
  });
}
