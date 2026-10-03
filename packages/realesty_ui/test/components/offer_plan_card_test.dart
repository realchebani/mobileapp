import 'package:flutter_test/flutter_test.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(OfferPlanCard, () {
    testWidgets('shows every part', (tester) async {
      await tester.pumpRealesty(
        const OfferPlanCard(
          badgeLabel: 'Premium · 1 %',
          badgeVariant: RealestyBadgeVariant.premium,
          tagline: 'La sérénité totale',
          name: 'Le Premium',
          rate: '1 %',
          rateCaption: 'au succès',
          fees: '+ 299 €',
          commission: 'Soit ~5 250 €',
          features: ['A', 'B'],
        ),
      );
      for (final text in [
        'Premium · 1 %',
        'La sérénité totale',
        'Le Premium',
        '1 %',
        'au succès',
        '+ 299 €',
        'Soit ~5 250 €',
        'A',
        'B',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('without fees nor commission', (tester) async {
      await tester.pumpRealesty(
        const OfferPlanCard(
          badgeLabel: 'Expert',
          badgeVariant: RealestyBadgeVariant.expert,
          tagline: 't',
          name: 'n',
          rate: '3 %',
          rateCaption: 'c',
          features: [],
        ),
      );
      expect(find.text('3 %'), findsOneWidget);
    });
  });
}
