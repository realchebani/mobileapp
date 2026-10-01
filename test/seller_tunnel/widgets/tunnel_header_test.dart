import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group(TunnelHeader, () {
    testWidgets('shows the step caption, title, pill and progress', (
      tester,
    ) async {
      var backs = 0;
      await tester.pumpApp(
        TunnelHeader(step: SellerTunnelStep.owners, onBack: () => backs++),
      );

      expect(find.text('Étape 1 · Propriétaires'), findsOneWidget);
      expect(find.text('Audit de votre bien'), findsOneWidget);
      expect(find.text('Écran'), findsOneWidget);
      final progress = tester.widget<SegmentedProgress>(
        find.byType(SegmentedProgress),
      );
      expect(progress.total, 7);
      expect(progress.completed, 1);
      expect(progress.semanticLabel, 'Étape 1 sur 7');

      await tester.tap(find.bySemanticsLabel('Retour'));
      expect(backs, 1);
    });

    testWidgets('shows the voice pill, a custom title and no back button', (
      tester,
    ) async {
      await tester.pumpApp(
        const TunnelHeader(
          step: SellerTunnelStep.lifestyle,
          onBack: null,
          title: 'Audit technique',
        ),
      );

      expect(find.text('Étape 6 · Cadre de vie'), findsOneWidget);
      expect(find.text('Audit technique'), findsOneWidget);
      expect(find.text('Vocal'), findsOneWidget);
      expect(find.bySemanticsLabel('Retour'), findsNothing);
    });

    testWidgets('shows the step counter', (tester) async {
      await tester.pumpApp(
        TunnelHeader(step: SellerTunnelStep.surfaces, onBack: () {}),
      );
      expect(find.text('5/7'), findsOneWidget);
      expect(find.text('Étape 5 · Pièces'), findsOneWidget);
    });

    testWidgets('can hide the right side or show a close button', (
      tester,
    ) async {
      await tester.pumpApp(
        TunnelHeader(
          step: SellerTunnelStep.documents,
          onBack: () {},
          mode: TunnelHeaderMode.none,
        ),
      );
      expect(find.text('7/7'), findsNothing);

      var closes = 0;
      await tester.pumpApp(
        TunnelHeader(
          step: SellerTunnelStep.submitted,
          onBack: () {},
          onClose: () => closes++,
        ),
      );
      expect(find.text('Étape 7 · Documents'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Enregistrer et quitter'));
      expect(closes, 1);
    });
  });
}
