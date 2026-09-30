import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('SectionLabel renders uppercase', (tester) async {
    await tester.pumpApp(const SectionLabel('Type de bien'));
    expect(find.text('TYPE DE BIEN'), findsOneWidget);
  });

  testWidgets('SectionTitle renders the title and trailing', (tester) async {
    await tester.pumpApp(
      const Column(
        children: [
          SectionTitle('Atouts', trailing: Text('3')),
          SectionTitle('Carte d’identité'),
        ],
      ),
    );
    expect(find.text('Atouts'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Carte d’identité'), findsOneWidget);
  });
}
