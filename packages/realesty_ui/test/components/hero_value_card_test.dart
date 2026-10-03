import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(HeroValueCard, () {
    testWidgets('renders every part and the action', (tester) async {
      var taps = 0;
      await tester.pumpRealesty(
        HeroValueCard(
          header: const Text('12 rue de la Colombe'),
          caption: 'Valeur certifiée',
          badgeLabel: 'Certifié',
          value: '525 000 €',
          details: 'Fourchette',
          expertLabel: 'Validé par Julien M.',
          actionLabel: 'Télécharger',
          actionIcon: RealestyIcons.download,
          onAction: () => taps++,
        ),
      );
      expect(find.text('12 rue de la Colombe'), findsOneWidget);
      expect(find.text('VALEUR CERTIFIÉE'), findsOneWidget);
      expect(find.text('Certifié'), findsOneWidget);
      expect(find.text('Fourchette'), findsOneWidget);
      // Initials derived from the label when not given.
      expect(find.text('VP'), findsOneWidget);
      await tester.tap(find.text('Télécharger'));
      expect(taps, 1);
    });

    testWidgets('only the caption and value are required', (tester) async {
      await tester.pumpRealesty(
        const HeroValueCard(caption: 'Avis', value: '1 €'),
      );
      expect(find.text('1 €'), findsOneWidget);
      expect(find.byType(HeroBadge), findsNothing);
      expect(find.byType(InitialsAvatar), findsNothing);
    });
  });
}
