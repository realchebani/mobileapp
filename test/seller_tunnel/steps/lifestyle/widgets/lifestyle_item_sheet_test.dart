import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/lifestyle_item_sheet.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

void main() {
  group('LifestyleItemSheet', () {
    testWidgets('validates the label before returning it', (tester) async {
      LifestyleItemSheetResult? result;
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showLifestyleItemSheet(
              context,
              kind: LifestyleItemKind.asset,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.enterText(field, ' ab ');
      await tester.tap(find.text('Ajouter'));
      await tester.pump();
      expect(find.text('Saisissez au moins 3 caractères'), findsOneWidget);
      await tester.enterText(field, 'abc');
      await tester.pump();
      expect(find.text('Saisissez au moins 3 caractères'), findsNothing);
      await tester.enterText(field, '  Calme  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, isA<LifestyleItemSaved>());
      expect((result! as LifestyleItemSaved).label, 'Calme');
    });

    testWidgets('does not show errors before the first submission', (
      tester,
    ) async {
      await tester.pumpApp(
        const Material(
          child: LifestyleItemSheet(
            kind: LifestyleItemKind.watchPoint,
            initial: 'Rue',
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(find.text('Saisissez au moins 3 caractères'), findsNothing);
      expect(find.text('Modifier le point de vigilance'), findsOneWidget);
    });
  });
}
