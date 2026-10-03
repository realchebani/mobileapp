import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';
import '../pump_vault.dart';
import '../vault_fixtures.dart';

void main() {
  late VaultTestKit kit;

  setUpAll(loadRealestyFonts);
  setUp(() => kit = VaultTestKit());

  Future<void> open(
    WidgetTester tester,
    String title, {
    VaultRubric? rubric,
  }) async {
    await kit.pump(
      tester,
      VaultDocumentsPage(
        target: const VaultTarget.property('property-id'),
        rubric: rubric ?? VaultRubric.energy,
        services: kit.services,
      ),
      height: 1600,
    );
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  group('VaultDocumentSheet', () {
    testWidgets('shows a document, its sharing and opens it', (tester) async {
      kit.documents = [
        document(
          'dpe',
          kind: DocumentKind.dpe,
          title: 'Mon DPE',
          status: DocumentStatus.analyzed,
          extracted: const {
            'classe': 'C',
            'annee': 2024,
            'nested': {'a': 1},
          },
          visibility: const {DocumentVisibility.notary},
        ),
      ];
      when(
        () => kit.repository.getDocumentUrl(
          any(),
          expiresIn: any(named: 'expiresIn'),
        ),
      ).thenAnswer((_) async => 'https://signed/dpe');
      when(() => kit.repository.setDocumentVisibility(any(), any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments[1] as Set<DocumentVisibility>,
      );
      when(() => kit.repository.downloadDocument(any()))
          .thenAnswer((_) async => Uint8List.fromList([1]));
      await open(tester, 'Mon DPE');
      expect(find.text('Qui peut voir ce document ?'), findsOneWidget);
      expect(find.text('Informations extraites'), findsOneWidget);
      expect(find.text('classe'), findsOneWidget);
      expect(find.text('2024'), findsOneWidget);
      expect(find.text('nested'), findsNothing);
      expect(find.text('Supprimer'), findsNothing);
      expect(find.text('Remplacer'), findsNothing);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      verify(
        () => kit.repository.setDocumentVisibility('dpe', {
          DocumentVisibility.notary,
          DocumentVisibility.buyers,
        }),
      ).called(1);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      verify(
        () => kit.repository.setDocumentVisibility('dpe', {
          DocumentVisibility.buyers,
        }),
      ).called(1);

      await tester.ensureVisible(find.text('Ouvrir'));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(kit.opened.single.toString(), 'https://signed/dpe');
      await tester.ensureVisible(find.text('Télécharger'));
      await tester.tap(find.text('Télécharger'));
      await tester.pumpAndSettle();
      expect(kit.shared, ['dpe.pdf']);
    });

    testWidgets('renames a document', (tester) async {
      kit.documents = [document('dpe', kind: DocumentKind.dpe)];
      when(() => kit.repository.renameDocument(any(), any())).thenAnswer(
        (_) async => document('dpe', kind: DocumentKind.dpe, title: 'DPE 2024'),
      );
      await open(tester, 'DPE');
      await tester.tap(find.bySemanticsLabel('Renommer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DPE 2024');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      verify(() => kit.repository.renameDocument('dpe', 'DPE 2024')).called(1);
      expect(find.text('DPE 2024'), findsWidgets);
      // Submitting with the keyboard too.
      await tester.tap(find.bySemanticsLabel('Renommer'));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      verify(() => kit.repository.renameDocument('dpe', 'DPE 2024')).called(1);
      // Dismissed: nothing.
      await tester.tap(find.bySemanticsLabel('Renommer'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      verifyNever(() => kit.repository.renameDocument('dpe', any()));
    });

    testWidgets('an identity document stays private', (tester) async {
      kit.documents = [
        document(
          'id',
          kind: DocumentKind.identityDocument,
          ownerRef: 'owner-1',
        ),
      ];
      await open(
        tester,
        'Pièce d’identité · Sophie Durand',
        rubric: VaultRubric.identity,
      );
      expect(find.text('Privé · non partageable'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('deletes an unverified addition, after confirming', (
      tester,
    ) async {
      kit.documents = [document('dpe', kind: DocumentKind.dpe, added: true)];
      when(() => kit.repository.deleteDocument(any())).thenAnswer((_) async {});
      await open(tester, 'DPE');
      expect(find.text('Ajouté après l’envoi'), findsWidgets);
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Supprimer définitivement ce document ?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Supprimer').last);
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      expect(find.text('Qui peut voir ce document ?'), findsNothing);
      expect(find.text('Document supprimé.'), findsOneWidget);
    });

    testWidgets('a failed delete keeps the sheet', (tester) async {
      kit.documents = [document('dpe', kind: DocumentKind.dpe, added: true)];
      when(() => kit.repository.deleteDocument(any()))
          .thenThrow(const PropertyDeleteFailure());
      await open(tester, 'DPE');
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Supprimer').last);
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      expect(find.text('Qui peut voir ce document ?'), findsOneWidget);
    });

    testWidgets('replaces a rejected document', (tester) async {
      kit.documents = [
        document(
          'dpe',
          kind: DocumentKind.dpe,
          status: DocumentStatus.rejected,
          rejectedReason: 'illisible',
        ),
      ];
      when(() => kit.picker.pick(DocumentSource.photos)).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List.fromList([1]),
          name: 'dpe.pdf',
          path: 'dpe.pdf',
        ),
      );
      kit.uploads(document('new', kind: DocumentKind.dpe, added: true));
      when(
        () => kit.repository.replaceDocument(
          oldId: any(named: 'oldId'),
          newId: any(named: 'newId'),
        ),
      ).thenAnswer((_) async {});
      await open(tester, 'DPE');
      expect(
        find.text('L’expert demande de remplacer ce document : illisible'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Remplacer'));
      await tester.tap(find.text('Remplacer'));
      await tester.pumpAndSettle();
      expect(find.text('Remplacer le document'), findsOneWidget);
      await tester.tap(find.text('Photothèque'));
      await tester.pumpAndSettle();
      expect(find.text('Document remplacé.'), findsOneWidget);
      // The rejected one is replaced: the sheet closed with it.
      expect(find.text('Qui peut voir ce document ?'), findsNothing);
    });

    testWidgets('a replacement can be abandoned', (tester) async {
      kit.documents = [
        document(
          'dpe',
          kind: DocumentKind.dpe,
          status: DocumentStatus.rejected,
        ),
      ];
      when(() => kit.picker.pick(any())).thenAnswer((_) async => null);
      await open(tester, 'DPE');
      expect(
        find.text('L’expert demande de remplacer ce document.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Remplacer'));
      await tester.tap(find.text('Remplacer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();
      expect(find.text('Qui peut voir ce document ?'), findsOneWidget);
      await tester.ensureVisible(find.text('Remplacer'));
      await tester.tap(find.text('Remplacer'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Qui peut voir ce document ?'), findsOneWidget);
    });
  });
}
