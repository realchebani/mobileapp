import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(RealestyIconButton, () {
    testWidgets('light variant is a 44 white circle', (tester) async {
      var taps = 0;
      await tester.pumpRealesty(
        RealestyIconButton(
          icon: RealestyIcons.chevronLeft,
          semanticLabel: 'Retour',
          onPressed: () => taps++,
        ),
      );
      expect(
        tester.getSize(find.byType(RealestyIconButton)),
        const Size(44, 44),
      );
      final icon = tester.widget<RealestyIcon>(find.byType(RealestyIcon));
      expect(icon.color, c.encre);
      await tester.tap(find.bySemanticsLabel('Retour'));
      expect(taps, 1);
    });

    testWidgets('dark variant uses Nuit 2 and a white icon', (tester) async {
      await tester.pumpRealesty(
        RealestyIconButton(
          icon: RealestyIcons.close,
          semanticLabel: 'Fermer',
          dark: true,
          onPressed: () {},
        ),
      );
      final icon = tester.widget<RealestyIcon>(find.byType(RealestyIcon));
      expect(icon.color, c.nuitTexte);
    });
  });

  group(RealestyMicButton, () {
    testWidgets('is a 56 green circle', (tester) async {
      var taps = 0;
      await tester.pumpRealesty(RealestyMicButton(onPressed: () => taps++));
      expect(
        tester.getSize(find.byType(RealestyMicButton)),
        const Size(56, 56),
      );
      await tester.tap(find.bySemanticsLabel('Parler à l’agent'));
      expect(taps, 1);
    });
  });
}
