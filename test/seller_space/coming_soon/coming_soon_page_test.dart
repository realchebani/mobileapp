import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/seller_space.dart';

import '../../helpers/helpers.dart';

void main() {
  group(ComingSoonPage, () {
    testWidgets('visits and vault placeholders', (tester) async {
      await tester.pumpApp(const Builder(builder: ComingSoonPage.visits));
      expect(find.text('Demandes de visite'), findsOneWidget);
      expect(find.text('Bientôt'), findsOneWidget);

      await tester.pumpApp(const Builder(builder: ComingSoonPage.vault));
      expect(find.text('Coffre-fort'), findsOneWidget);
      expect(find.textContaining('rangés par rubrique'), findsOneWidget);
    });
  });
}
