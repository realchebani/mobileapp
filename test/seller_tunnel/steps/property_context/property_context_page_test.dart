import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('PropertyContextPage shows the provisional context step', (
    tester,
  ) async {
    await tester.pumpTunnelPage(const PropertyContextPage());
    expect(
      tester.widget<ProvisionalStepView>(find.byType(ProvisionalStepView)).step,
      SellerTunnelStep.context,
    );
  });
}
