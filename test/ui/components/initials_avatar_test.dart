import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(InitialsAvatar, () {
    test('of builds up to two initials', () {
      expect(InitialsAvatar.of('Julien M.'), 'JM');
      expect(InitialsAvatar.of('jean-pierre de la tour'), 'JP');
      expect(InitialsAvatar.of('  '), '?');
    });

    testWidgets('light and dark variants', (tester) async {
      await tester.pumpRealesty(
        const Row(
          children: [InitialsAvatar('SD'), InitialsAvatar('JM', onDark: true)],
        ),
      );
      final light = tester.widget<Text>(find.text('SD'));
      final dark = tester.widget<Text>(find.text('JM'));
      expect(light.style?.color, c.encre);
      expect(dark.style?.color, c.nuitTexte);
    });
  });
}
