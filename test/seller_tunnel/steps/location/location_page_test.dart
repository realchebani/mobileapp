import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('LocationPage shows the provisional location step', (
    tester,
  ) async {
    await tester.pumpTunnelPage(const LocationPage());
    expect(
      tester.widget<ProvisionalStepView>(find.byType(ProvisionalStepView)).step,
      SellerTunnelStep.location,
    );
  });
}
