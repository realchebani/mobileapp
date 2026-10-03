import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(RealestySwitch, () {
    testWidgets('toggles, and is disabled without onChanged', (tester) async {
      bool? changed;
      await tester.pumpRealesty(
        RealestySwitch(
          value: false,
          onChanged: (value) => changed = value,
          semanticLabel: 'Option',
        ),
      );
      await tester.tap(find.byType(RealestySwitch));
      expect(changed, isTrue);
      await tester.pumpRealesty(
        const RealestySwitch(
          value: true,
          onChanged: null,
          semanticLabel: 'Option',
        ),
      );
      await tester.tap(find.byType(RealestySwitch));
      expect(changed, isTrue);
    });
  });

  group(SwitchRow, () {
    testWidgets('shows its texts and toggles', (tester) async {
      bool? changed;
      await tester.pumpRealesty(
        SwitchRow(
          title: 'Retouche',
          subtitle: 'Luminosité',
          badge: const RealestyBadge(label: 'Bientôt'),
          value: true,
          onChanged: (value) => changed = value,
        ),
      );
      expect(find.text('Luminosité'), findsOneWidget);
      expect(find.text('Bientôt'), findsOneWidget);
      await tester.tap(find.byType(RealestySwitch));
      expect(changed, isFalse);
      await tester.pumpRealesty(
        const SwitchRow(title: 'Seul', value: false, onChanged: null),
      );
      expect(find.text('Seul'), findsOneWidget);
    });
  });
}
