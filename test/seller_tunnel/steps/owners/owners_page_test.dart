import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('OwnersPage shows the provisional owners step', (tester) async {
    await tester.pumpTunnelPage(const OwnersPage());
    expect(
      tester.widget<ProvisionalStepView>(find.byType(ProvisionalStepView)).step,
      SellerTunnelStep.owners,
    );
  });
}
