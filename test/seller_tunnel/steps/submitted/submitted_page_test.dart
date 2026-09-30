import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('SubmittedPage shows the provisional submitted step', (
    tester,
  ) async {
    await tester.pumpTunnelPage(const SubmittedPage());
    expect(
      tester.widget<ProvisionalStepView>(find.byType(ProvisionalStepView)).step,
      SellerTunnelStep.submitted,
    );
  });
}
