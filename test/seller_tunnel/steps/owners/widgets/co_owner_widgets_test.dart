import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/co_owner_card.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/co_owner_sheet.dart';

import '../../../../helpers/helpers.dart';

Finder _sheetField(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

void main() {
  group(CoOwnerCard, () {
    testWidgets('shows the co-owner and its actions', (tester) async {
      var edited = 0;
      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: [
              CoOwnerCard(
                coOwner: const OwnerDraft(
                  firstName: 'Marc',
                  lastName: 'Durand',
                  phone: '+33 6 98 76 54 32',
                ),
                onEdit: () => edited++,
              ),
              const CoOwnerCard(
                coOwner: OwnerDraft(firstName: 'Léa', lastName: 'Roy'),
                onEdit: null,
              ),
            ],
          ),
        ),
      );

      expect(find.text('MD'), findsOneWidget);
      expect(find.text('Marc Durand'), findsOneWidget);
      expect(
        find.text('Co-propriétaire · 06\u00a098\u00a076\u00a054\u00a032'),
        findsOneWidget,
      );
      expect(find.text('Co-propriétaire'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Modifier Marc Durand'));
      expect(edited, 1);
    });
  });

  group(CoOwnerSheet, () {
    Future<List<CoOwnerSheetResult?>> open(
      WidgetTester tester, {
      OwnerDraft? initial,
    }) async {
      usePhoneSurface();
      final results = <CoOwnerSheetResult?>[];
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showCoOwnerSheet(context, initial: initial),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('validates then returns the new co-owner', (tester) async {
      final results = await open(tester);
      expect(find.text('Ajouter un co-propriétaire'), findsOneWidget);

      await tester.tap(find.text('Ajouter'));
      await tester.pump();
      expect(find.text('Champ obligatoire'), findsNWidgets(3));

      await tester.enterText(_sheetField('Prénom'), 'Marc');
      await tester.enterText(_sheetField('Nom'), 'Durand');
      await tester.enterText(_sheetField('Téléphone'), '06 98');
      await tester.enterText(_sheetField('E-mail (facultatif)'), 'marc@');
      await tester.pump();
      expect(find.text('Champ obligatoire'), findsNothing);
      expect(
        find.text(
          'Numéro invalide, par exemple 06\u00a012\u00a034\u00a056\u00a078',
        ),
        findsOneWidget,
      );
      expect(find.text('Adresse e-mail invalide'), findsOneWidget);

      await tester.enterText(_sheetField('Téléphone'), '06 98 76 54 32');
      await tester.enterText(_sheetField('E-mail (facultatif)'), '');
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(
        (results.single! as CoOwnerSaved).coOwner,
        const OwnerDraft(
          firstName: 'Marc',
          lastName: 'Durand',
          phone: '06 98 76 54 32',
        ),
      );
      expect(find.text('Supprimer ce co-propriétaire'), findsNothing);
    });

    testWidgets('edits a co-owner and submits from the keyboard', (
      tester,
    ) async {
      const initial = OwnerDraft(
        id: 'o2',
        firstName: 'Marc',
        lastName: 'Durand',
        phone: '06 98 76 54 32',
      );
      final results = await open(tester, initial: initial);
      expect(find.text('Modifier le co-propriétaire'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);

      await tester.enterText(_sheetField('E-mail (facultatif)'), 'm@d.fr');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        (results.single! as CoOwnerSaved).coOwner,
        const OwnerDraft(
          firstName: 'Marc',
          lastName: 'Durand',
          phone: '06 98 76 54 32',
          email: 'm@d.fr',
        ),
      );
    });

    testWidgets('deletes an edited co-owner', (tester) async {
      final results = await open(
        tester,
        initial: const OwnerDraft(firstName: 'Marc', lastName: 'Durand'),
      );
      await tester.tap(find.text('Supprimer ce co-propriétaire'));
      await tester.pumpAndSettle();
      expect(results.single, isA<CoOwnerDeleted>());
    });

    testWidgets('returns null when dismissed', (tester) async {
      final results = await open(tester);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });
}
