import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(KeyValueRow, () {
    testWidgets('plain and emphasized rows', (tester) async {
      await tester.pumpRealesty(
        const Column(
          children: [
            KeyValueRow(label: 'Prix', value: '1 €', trailing: Text('tag')),
            KeyValueRow(
              label: 'Total',
              value: '2 €',
              emphasized: true,
              divider: false,
              valueColor: Color(0xFF00FF00),
            ),
          ],
        ),
      );
      expect(
        tester.widget<Text>(find.text('Prix')).style?.color,
        c.texteDiscret,
      );
      expect(tester.widget<Text>(find.text('Total')).style?.color, c.encre);
      expect(
        tester.widget<Text>(find.text('2 €')).style?.color,
        const Color(0xFF00FF00),
      );
      expect(find.text('tag'), findsOneWidget);
    });
  });
}
