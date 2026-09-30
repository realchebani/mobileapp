import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(AgentBubble, () {
    testWidgets('light variant', (tester) async {
      await tester.pumpRealesty(const AgentBubble(message: 'Bonjour'));
      expect(find.text('Agent Realesty'), findsOneWidget);
      expect(find.byType(AgentAvatar), findsOneWidget);
      expect(tester.widget<Text>(find.text('Bonjour')).style?.color, c.encre);
      expect(tester.getSize(find.byType(AgentAvatar)), const Size(36, 36));
    });

    testWidgets('night variant', (tester) async {
      await tester.pumpRealesty(
        const AgentBubble(
          message: 'Bonsoir',
          senderName: 'Agent',
          onDark: true,
        ),
      );
      expect(find.text('Agent'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Bonsoir')).style?.color,
        c.nuitTexte,
      );
    });
  });

  group(UserBubble, () {
    testWidgets('is right aligned and capped at 78%', (tester) async {
      await tester.pumpRealesty(
        const SizedBox(
          width: 300,
          child: UserBubble(
            message: 'Un message assez long pour passer à la ligne',
          ),
        ),
      );
      final box = tester.getRect(find.byType(Container).last);
      expect(box.width, lessThanOrEqualTo(300 * 0.78));
      expect(
        tester.widget<Text>(find.textContaining('Un message')).style?.color,
        c.surface,
      );
    });

    testWidgets('night variant', (tester) async {
      await tester.pumpRealesty(const UserBubble(message: 'Oui', onDark: true));
      expect(tester.widget<Text>(find.text('Oui')).style?.color, c.encre);
    });
  });
}
