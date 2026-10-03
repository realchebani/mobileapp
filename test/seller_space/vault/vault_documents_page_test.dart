import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import 'pump_vault.dart';
import 'vault_fixtures.dart';

void main() {
  late VaultTestKit kit;

  setUpAll(loadRealestyFonts);
  setUp(() => kit = VaultTestKit());

  VaultDocumentsPage page({VaultRubric? rubric, VaultTarget? target}) =>
      VaultDocumentsPage(
        target: target ?? const VaultTarget.property('property-id'),
        rubric: rubric,
        services: kit.services,
      );

  group(VaultDocumentsPage, () {
    testWidgets('opens the asked rubric, folds and unfolds them', (
      tester,
    ) async {
      kit.documents = [
        document('dpe', kind: DocumentKind.dpe, title: 'Mon DPE', added: true),
        document('deed', kind: DocumentKind.titleDeed),
      ];
      await kit.pump(tester, page(rubric: VaultRubric.energy));
      expect(find.text('Mes documents'), findsOneWidget);
      expect(find.text('Coffre-fort · Espace vendeur'), findsOneWidget);
      expect(find.text('Mon DPE'), findsOneWidget);
      expect(find.text('Titre de propriété'), findsNothing);
      expect(find.text('3 documents'), findsOneWidget);
      expect(find.text('2 à ajouter'), findsWidgets);
      expect(
        find.text(
          'Il manque votre pièce d’identité pour signer le mandat. '
          'Scannez-la en 30 secondes.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tout déplier'));
      await tester.pumpAndSettle();
      expect(find.text('Titre de propriété'), findsOneWidget);
      await tester.tap(find.text('Tout replier'));
      await tester.pumpAndSettle();
      expect(find.text('Mon DPE'), findsNothing);
      await tester.tap(find.text('Énergie'));
      await tester.pumpAndSettle();
      expect(find.text('Mon DPE'), findsOneWidget);
      await tester.tap(find.text('Énergie'));
      await tester.pumpAndSettle();
      expect(find.text('Mon DPE'), findsNothing);
    });

    testWidgets('relays what the expert asks to replace', (tester) async {
      kit
        ..owners = const []
        ..documents = [
          document('deed', kind: DocumentKind.titleDeed),
          document('id', kind: DocumentKind.identityDocument),
          document(
            'tax',
            kind: DocumentKind.propertyTax,
            status: DocumentStatus.rejected,
            rejectedReason: 'illisible',
          ),
        ];
      await kit.pump(tester, page());
      expect(
        find.text('L’expert demande de remplacer : Taxe foncière (illisible).'),
        findsOneWidget,
      );
      expect(find.text('À remplacer'), findsWidgets);
    });

    testWidgets('a rejection without reason', (tester) async {
      kit
        ..owners = const []
        ..documents = [
          document('deed', kind: DocumentKind.titleDeed),
          document('id', kind: DocumentKind.identityDocument),
          document(
            'tax',
            kind: DocumentKind.propertyTax,
            status: DocumentStatus.rejected,
          ),
        ];
      await kit.pump(tester, page());
      expect(
        find.text('L’expert demande de remplacer : Taxe foncière.'),
        findsOneWidget,
      );
    });

    testWidgets('opens the valuation report, or V9b without a PDF', (
      tester,
    ) async {
      when(
        () => kit.valuations.getReportUrl(
          any(),
          expiresIn: any(named: 'expiresIn'),
        ),
      ).thenAnswer((_) async => 'https://signed/report');
      await kit.pump(tester, page(rubric: VaultRubric.mandates));
      await tester.dragUntilVisible(
        find.text('Avis de valeur certifié'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.ensureVisible(find.text('Avis de valeur certifié'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avis de valeur certifié'));
      await tester.pumpAndSettle();
      expect(kit.opened.single.toString(), 'https://signed/report');
    });

    testWidgets('a valuation without PDF opens V9b', (tester) async {
      kit.valuation = Valuation(
        id: 'v',
        propertyId: 'property-id',
        valueEur: 500000,
        lowEur: 480000,
        highEur: 520000,
        expertDisplayName: 'Julien M.',
        certifiedAt: DateTime(2026, 9, 25),
        validUntil: DateTime(2026, 12, 25),
      );
      await kit.pump(tester, page(rubric: VaultRubric.mandates));
      await tester.dragUntilVisible(
        find.text('Validé le 25/09/2026 par Julien M.'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.ensureVisible(find.text('Avis de valeur certifié'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avis de valeur certifié'));
      verify(() => kit.router.go(AppRoutes.sellerReport('property-id')))
          .called(1);
    });

    testWidgets('an empty rubric; the Realesty one has its own text', (
      tester,
    ) async {
      kit.valuation = null;
      await kit.pump(tester, page());
      expect(find.text('Aucun document pour l’instant.'), findsWidgets);
      await tester.dragUntilVisible(
        find.text(
          'Votre avis de valeur certifié et vos mandats apparaîtront ici.',
        ),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.dragUntilVisible(
        find.textContaining('Realesty accède à vos documents'),
        find.byType(ListView),
        const Offset(0, -300),
      );
    });

    testWidgets('scans a missing identity document', (tester) async {
      when(() => kit.picker.scanPages(maxPages: any(named: 'maxPages')))
          .thenAnswer((_) async => null);
      await kit.pump(tester, page(rubric: VaultRubric.identity));
      expect(find.text('Pièce d’identité · Sophie Durand'), findsOneWidget);
      await tester.tap(find.text('Scanner').first);
      await tester.pumpAndSettle();
      verify(() => kit.picker.scanPages(maxPages: any(named: 'maxPages')))
          .called(1);
    });

    testWidgets('scans and sends the PDF of a missing document', (
      tester,
    ) async {
      when(
        () => kit.picker.scanPages(maxPages: any(named: 'maxPages')),
      ).thenAnswer(
        (_) async => [
          XFile.fromData(Uint8List.fromList([1]), name: 'p.jpg', path: 'p.jpg'),
        ],
      );
      kit.uploads(document('id', kind: DocumentKind.identityDocument));
      await kit.pump(tester, page(rubric: VaultRubric.identity), height: 1400);
      await tester.tap(find.text('Scanner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminer'));
      await tester.pumpAndSettle();
      verify(
        () => kit.repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: DocumentKind.identityDocument,
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: 'application/pdf',
          title: any(named: 'title'),
          ownerRef: 'owner-1',
        ),
      ).called(1);
    });

    testWidgets('adds to a rubric', (tester) async {
      await kit.pump(tester, page(rubric: VaultRubric.tax));
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      // One kind in the rubric: straight to the source.
      expect(find.text('Ajouter un document'), findsWidgets);
      expect(find.text('Photothèque'), findsOneWidget);
    });

    testWidgets('a lot shows the property of each document', (tester) async {
      const lot = PropertyLot(id: 'lot-id', ownerId: 'user-id', name: 'Lot');
      const house = Property(
        id: 'property-id',
        ownerId: 'user-id',
        status: PropertyStatus.certified,
        propertyType: PropertyType.house,
        lotId: 'lot-id',
        addressCity: 'Chaponost',
      );
      const garage = Property(
        id: 'draft-id',
        ownerId: 'user-id',
        propertyType: PropertyType.parking,
        lotId: 'lot-id',
        addressCity: 'Lyon',
      );
      kit.documents = [
        document('tax', propertyId: 'draft-id', kind: DocumentKind.propertyTax),
      ];
      await kit.pump(
        tester,
        page(target: const VaultTarget.lot('lot-id'), rubric: VaultRubric.tax),
        properties: const [house, garage],
        lots: const [lot],
      );
      expect(find.text('Lot'), findsOneWidget);
      expect(find.textContaining('· Taxe foncière'), findsOneWidget);
      // Adding asks for the property first.
      await tester.tap(find.bySemanticsLabel('Ajouter un document'));
      await tester.pumpAndSettle();
      expect(find.text('Pour quel bien ?'), findsOneWidget);
    });

    testWidgets('a property that no longer exists', (tester) async {
      await kit.pump(tester, page(target: const VaultTarget.property('nope')));
      expect(find.text('Ce bien n’existe plus.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(kit.router.pop).called(1);
      when(() => kit.router.canPop()).thenReturn(false);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => kit.router.go(AppRoutes.sellerVault)).called(1);
    });

    testWidgets('a failure offers to retry', (tester) async {
      when(() => kit.repository.getDocumentsOf(any()))
          .thenThrow(const PropertyLoadFailure());
      await kit.pump(tester, page());
      expect(
        find.text('Vos documents n’ont pas pu être chargés.'),
        findsOneWidget,
      );
      when(() => kit.repository.getDocumentsOf(any()))
          .thenAnswer((_) async => []);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Mes documents'), findsOneWidget);
    });
  });
}
