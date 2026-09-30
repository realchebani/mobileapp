import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('AgentIntro shows the agent bubble', (tester) async {
    await tester.pumpApp(const AgentIntro(message: 'Bonjour !', onDark: true));
    final bubble = tester.widget<AgentBubble>(find.byType(AgentBubble));
    expect(bubble.message, 'Bonjour !');
    expect(bubble.senderName, 'Agent Realesty');
    expect(bubble.onDark, isTrue);
  });
}
