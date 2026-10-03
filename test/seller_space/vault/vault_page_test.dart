import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_target_selector.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';
import 'pump_vault.dart';
import 'vault_fixtures.dart';

void main() {
  late VaultTestKit kit;

  setUpAll(loadRealestyFonts);
  setUp(() => kit = VaultTestKit());

  group(VaultPage, () {
    testWidgets('shows the rubrics, the recents and the missing ones', (
      tester,
    ) async {
      kit.documents = [
        document(
          'deed',
          kind: DocumentKind.titleDeed,
          verifiedAt: DateTime(2026),
        ),
        document(
          'tax',
          kind: DocumentKind.propertyTax,
          status: DocumentStatus.rejected,
          title: 'Taxe foncière 2025',
        ),
      ];
      await kit.pump(tester, VaultPage(services: kit.services));
      expect(find.text('Coffre-fort'), findsOneWidget);
      expect(find.byType(VaultTargetSelector), findsNothing);
      expect(find.text('Propriété'), findsOneWidget);
      expect(find.text('1 document · tous vérifiés'), findsNWidgets(2));
      expect(find.text('1 document · 1 à remplacer'), findsOneWidget);
      expect(find.text('2 à ajouter'), findsOneWidget);
      expect(find.text('Avis de valeur certifié'), findsOneWidget);
      await tester.tap(find.text('Énergie'));
      verify(
        () => kit.router.push<Object?>(
          AppRoutes.sellerVaultProperty('property-id', rubric: 'energie'),
        ),
      ).called(1);
      await tester.dragUntilVisible(
        find.text('Récents'.toUpperCase()),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('Pièce d’identité · Sophie Durand'), findsOneWidget);
      await tester.dragUntilVisible(
        find.textContaining('Documents chiffrés'),
        find.byType(ListView),
        const Offset(0, -200),
      );
    });

    testWidgets('searches the documents', (tester) async {
      kit.documents = [
        document('tax', kind: DocumentKind.propertyTax, title: 'Taxe foncière'),
      ];
      await kit.pump(tester, VaultPage(services: kit.services));
      await tester.enterText(find.byType(TextField), 'fonciere');
      await tester.pumpAndSettle();
      expect(find.text('1 résultat'.toUpperCase()), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(
        find.text('Aucun document ne correspond à votre recherche.'),
        findsOneWidget,
      );
    });

    testWidgets('chooses a lot among several properties', (tester) async {
      const lot = PropertyLot(
        id: 'lot-id',
        ownerId: 'user-id',
        name: 'Maison + garage',
      );
      const inLot = Property(
        id: 'draft-id',
        ownerId: 'user-id',
        propertyType: PropertyType.parking,
        lotId: 'lot-id',
        addressCity: 'Lyon',
      );
      const sent = Property(
        id: 'property-id',
        ownerId: 'user-id',
        status: PropertyStatus.certified,
        propertyType: PropertyType.house,
        lotId: 'lot-id',
        addressCity: 'Chaponost',
      );
      kit.documents = [document('tax', kind: DocumentKind.propertyTax)];
      await kit.pump(
        tester,
        VaultPage(services: kit.services),
        properties: const [sent, inLot],
        lots: const [lot],
      );
      expect(find.text('Maison · Chaponost'), findsOneWidget);
      await tester.tap(find.text('Maison · Chaponost'));
      await tester.pumpAndSettle();
      expect(find.text('Quel bien ?'), findsOneWidget);
      await tester.tap(find.text('Maison + garage'));
      await tester.pumpAndSettle();
      expect(find.text('Maison + garage'), findsOneWidget);
      verify(() => kit.repository.getDocumentsOf(['property-id', 'draft-id']))
          .called(1);
      await tester.tap(find.text('Fiscalité'));
      verify(() => kit.router.push<Object?>(AppRoutes.sellerVaultLot('lot-id')))
          .called(1);
    });

    testWidgets('follows the properties of the seller', (tester) async {
      final properties = MockSellerPropertiesCubit();
      const empty = SellerPropertiesState(
        status: SellerPropertiesStatus.loading,
      );
      const loaded = SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [sentProperty],
      );
      const changed = SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [
          Property(
            id: 'property-id',
            ownerId: 'user-id',
            status: PropertyStatus.inReview,
          ),
        ],
      );
      whenListen(
        properties,
        Stream.fromIterable([loaded, changed]),
        initialState: empty,
      );
      when(properties.refresh).thenAnswer((_) async {});
      await kit.pump(
        tester,
        VaultPage(services: kit.services),
        propertiesCubit: properties,
      );
      verify(() => kit.repository.getDocumentsOf(['property-id'])).called(2);
    });

    testWidgets('without a property', (tester) async {
      await kit.pump(
        tester,
        VaultPage(services: kit.services),
        properties: const [],
      );
      expect(
        find.text(
          'Ajoutez un bien pour ranger ses documents dans votre coffre-fort.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Ajouter un bien'));
      verify(() => kit.router.go(AppRoutes.sellerNewProperty)).called(1);
    });

    testWidgets('a failure offers to retry, and pull to refresh', (
      tester,
    ) async {
      when(() => kit.repository.getDocumentsOf(any()))
          .thenThrow(const PropertyLoadFailure());
      await kit.pump(tester, VaultPage(services: kit.services));
      expect(
        find.text('Vos documents n’ont pas pu être chargés.'),
        findsOneWidget,
      );
      when(() => kit.repository.getDocumentsOf(any()))
          .thenAnswer((_) async => []);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Propriété'), findsOneWidget);
      await tester.fling(find.text('Propriété'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      verify(() => kit.repository.getDocumentsOf(any())).called(3);
    });

    testWidgets('adds a document from the files, then retries a failure', (
      tester,
    ) async {
      when(() => kit.picker.pick(DocumentSource.files)).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List.fromList([1]),
          name: 'dpe.pdf',
          path: 'dpe.pdf',
        ),
      );
      kit.uploads(document('new', kind: DocumentKind.dpe, added: true));
      await kit.pump(tester, VaultPage(services: kit.services));
      await tester.tap(find.bySemanticsLabel('Ajouter un document'));
      await tester.pumpAndSettle();
      expect(find.text('Quel document ?'), findsOneWidget);
      await tester.tap(find.text('DPE'));
      await tester.pumpAndSettle();
      expect(find.text('Fichiers'), findsOneWidget);
      expect(find.text('Depuis un autre bien'), findsNothing);
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();
      expect(find.text('Document ajouté.'), findsOneWidget);

      when(
        () => kit.repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
          title: any(named: 'title'),
          ownerRef: any(named: 'ownerRef'),
        ),
      ).thenThrow(const DocumentUploadFailure());
      await tester.tap(find.bySemanticsLabel('Ajouter un document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DPE').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();
      expect(find.text('L’envoi de « dpe.pdf » a échoué.'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('L’envoi de « dpe.pdf » a échoué.'), findsOneWidget);
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text('L’envoi de « dpe.pdf » a échoué.'), findsNothing);
    });
  });
}
