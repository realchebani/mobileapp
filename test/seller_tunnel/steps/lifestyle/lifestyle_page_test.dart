import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('LifestylePage shows the provisional lifestyle step', (
    tester,
  ) async {
    await tester.pumpTunnelPage(const LifestylePage());
    expect(
      tester.widget<ProvisionalStepView>(find.byType(ProvisionalStepView)).step,
      SellerTunnelStep.lifestyle,
    );
  });
}
