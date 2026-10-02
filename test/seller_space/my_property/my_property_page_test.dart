import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../helpers/helpers.dart';
import '../pump_seller_space.dart';

void main() {
  group(MyPropertyPage, () {
    testWidgets('draft: start or resume the audit', (tester) async {
      await tester.pumpSellerSpacePage(
        const MyPropertyPage(),
        sellerTunnelCubit: mockSellerTunnelCubit(),
      );
      expect(find.byType(SellerHomePage), findsOneWidget);
    });

    testWidgets('sent: the dashboard', (tester) async {
      await tester.pumpSellerSpacePage(const MyPropertyPage());
      expect(find.byType(DashboardPage), findsOneWidget);
    });
  });
}
