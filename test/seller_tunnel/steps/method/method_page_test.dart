import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('MethodPage shows the provisional method step', (tester) async {
    await tester.pumpTunnelPage(const MethodPage());
    expect(
      tester.widget<ProvisionalStepView>(find.byType(ProvisionalStepView)).step,
      SellerTunnelStep.method,
    );
  });
}
