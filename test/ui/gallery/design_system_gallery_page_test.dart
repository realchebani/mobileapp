import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

void main() {
  group(DesignSystemGalleryPage, () {
    Future<void> pumpGallery(WidgetTester tester) async {
      // A very tall surface so the whole ListView is built at once.
      tester.view.physicalSize = const Size(1200, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: realestyTheme(),
          home: DesignSystemGalleryPage(key: UniqueKey()),
        ),
      );
    }

    Future<void> tapAndExpectToast(
      WidgetTester tester,
      Finder finder,
      String message,
    ) async {
      await tester.tap(finder);
      await tester.pump();
      expect(find.text(message), findsWidgets);
    }

    testWidgets('renders every section', (tester) async {
      await pumpGallery(tester);
      for (final section in [
        'LOGO',
        'COULEURS',
        'TYPOGRAPHIE',
        'ICÔNES',
        'BOUTONS',
        'CHAMPS',
        'SÉLECTION',
        'BADGES & PROVENANCE',
        'PROGRESSION',
        'LISTE',
        'BANNIÈRES',
        'AGENT',
        'ESPACE VENDEUR',
        'MISE EN VENTE',
      ]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      expect(find.text('525\u00A0000\u00A0€'), findsOneWidget);
      expect(find.text('À compléter'), findsOneWidget);
      expect(
        find.byType(RealestyIcon),
        findsAtLeastNWidgets(RealestyIcons.values.length),
      );
    });

    testWidgets('buttons show snackbars', (tester) async {
      await pumpGallery(tester);
      await tapAndExpectToast(tester, find.text('Continuer'), 'Continuer');
      await tapAndExpectToast(tester, find.text('Parler à l’agent'), 'Accent');
      await tapAndExpectToast(
        tester,
        find.text('Envoyer mon dossier'),
        'Icône à droite',
      );
      await tapAndExpectToast(
        tester,
        find.text('Importer un document'),
        'Secondaire',
      );
      await tapAndExpectToast(tester, find.text('Passer cette étape'), 'Texte');
      await tapAndExpectToast(
        tester,
        find.text('Supprimer mon compte'),
        'Destructif',
      );
      await tapAndExpectToast(
        tester,
        find.bySemanticsLabel('Retour'),
        'Retour',
      );
      await tapAndExpectToast(
        tester,
        find.bySemanticsLabel('Fermer'),
        'Fermer',
      );
      await tapAndExpectToast(tester, find.byType(RealestyMicButton), 'Micro');
      await tapAndExpectToast(
        tester,
        find.text('Pièce d’identité'),
        'Document manquant',
      );
      await tester.tapOnText(
        find.textRange.ofSubstring('conditions générales'),
      );
      await tester.pump();
      expect(find.text('Conditions générales'), findsOneWidget);
      await tester.tap(find.text('Envoyer (chargement au tap)'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Envoyer (chargement au tap)'), findsOneWidget);
    });

    testWidgets('controls update their state', (tester) async {
      await pumpGallery(tester);

      await tester.tap(find.text('Recevoir les actualités du marché'));
      await tester.tap(find.textContaining('J’accepte'));
      await tester.tap(find.text('Garage'));
      await tester.tap(find.text('Jardin'));
      await tester.tap(find.text('Appartement'));
      await tester.tap(find.bySemanticsLabel('Augmenter Chambres'));
      await tester.pump();
      expect(find.text('4'), findsOneWidget);

      await tester.tap(find.text('Choisir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terrain'));
      await tester.pumpAndSettle();
      expect(find.text('Terrain'), findsOneWidget);
    });

    testWidgets('seller space components', (tester) async {
      await pumpGallery(tester);
      await tapAndExpectToast(
        tester,
        find.text('Voir le rapport complet'),
        'Rapport',
      );
      await tapAndExpectToast(
        tester,
        find.text('Mettre mon bien en vente'),
        'Mise en vente',
      );
      await tapAndExpectToast(
        tester,
        find.text('Suivi de mon dossier'),
        'Suivi',
      );
      await tester.tap(find.text('Compte'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('Compte')).style?.fontWeight,
        FontWeight.w700,
      );
    });

    testWidgets('sale components', (tester) async {
      await pumpGallery(tester);
      await tester.tap(find.byType(RealestySwitch));
      await tester.pump();
      expect(
        tester.widget<RealestySwitch>(find.byType(RealestySwitch)).value,
        isFalse,
      );
      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pump();
      expect(
        tester.widget<PriceRangeSlider>(find.byType(PriceRangeSlider)).value,
        greaterThan(525000),
      );
    });
  });
}
