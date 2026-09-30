import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('TechnicalPage shows the provisional technical step', (
    tester,
  ) async {
    await tester.pumpTunnelPage(const TechnicalPage());
    expect(
      tester.widget<ProvisionalStepView>(find.byType(ProvisionalStepView)).step,
      SellerTunnelStep.technical,
    );
  });
}
