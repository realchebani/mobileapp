import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_labels.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_target_selector.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';
import '../pump_vault.dart';
import '../vault_fixtures.dart';

void main() {
  final l10n = AppLocalizationsFr();

  setUpAll(loadRealestyFonts);

  test('every notice has a message', () {
    for (final notice in VaultNotice.values) {
      final (message, _) = vaultNoticeMessage(l10n, notice);
      expect(message, isNotEmpty);
    }
    expect(vaultNoticeMessage(l10n, VaultNotice.uploaded).$2, isFalse);
    expect(vaultNoticeMessage(l10n, VaultNotice.uploadFailed).$2, isTrue);
  });

  test('labels', () {
    expect(
      l10n.vaultDocumentDetails(
        document('a', mimeType: 'image/jpeg', sizeBytes: null),
      ),
      'Image · ajouté le 12/09/2026',
    );
    expect(
      l10n.vaultDocumentDetails(
        const PropertyDocument(
          id: 'a',
          propertyId: 'p',
          kind: DocumentKind.other,
          storagePath: 's',
        ),
      ),
      '',
    );
    expect(
      l10n.vaultStatusBadge(VaultDocumentStatus.analyzing).label,
      'Analyse en cours',
    );
    expect(
      l10n.vaultVisibility(const {
        DocumentVisibility.buyers,
        DocumentVisibility.notary,
      }),
      'Acquéreurs · Notaire',
    );
    expect(
      l10n.vaultDocumentTitle(document('a'), owner: sophie.copyWithName()),
      'Autre document',
    );
    for (final key in [
      'classe',
      'annee',
      'montant',
      'entreprise',
      'equipement',
      'date',
      'surface',
      'garantie',
    ]) {
      expect(l10n.vaultExtractedLabel(key), isNot(key));
    }
    expect(l10n.vaultExtractedLabel('date_pose'), 'Date pose');
    expect(l10n.vaultExtractedLabel('_'), '_');
    for (final rubric in VaultRubric.values) {
      expect(l10n.vaultRubric(rubric), isNotEmpty);
      expect(VaultLabels.rubricIcon(rubric), isNotNull);
    }
  });

  test('the label and members of an unknown target', () {
    const properties = SellerPropertiesState();
    expect(
      vaultTargetLabel(l10n, properties, const VaultTarget.property('x')),
      l10n.myPropertiesUntitled,
    );
    expect(
      vaultTargetMembers(properties, const VaultTarget.property('x')),
      isEmpty,
    );
  });

  test('equality of the add targets and contents', () {
    const a = VaultAddTarget(propertyId: 'p', kind: DocumentKind.dpe);
    expect(a.props, ['p', DocumentKind.dpe, null]);
    VaultContents build() => VaultContents.of(
      properties: const [sentProperty],
      documents: [document('a')],
    );
    expect(build(), build());
    expect(build().missing.first, build().missing.first);
    expect(build().sections.first, build().sections.first);
  });

  testWidgets('shareDocumentFile shares a temporary file, then deletes it', (
    tester,
  ) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    final calls = <MethodCall>[];
    var existed = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      final paths = (call.arguments as Map)['paths'] as List;
      existed = File(paths.single as String).existsSync();
      return 'dev.fluttercommunity.plus/share/success';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.runAsync(
      () => shareDocumentFile(
        Uint8List.fromList([1, 2]),
        'dir/a.pdf',
        'application/pdf',
      ),
    );
    expect(calls.single.method, 'share');
    expect(existed, isTrue);
    final path =
        ((calls.single.arguments as Map)['paths'] as List).single as String;
    expect(path, endsWith('/a.pdf'));
    expect(File(path).existsSync(), isFalse);
  });

  group('V18', () {
    late VaultTestKit kit;

    setUp(() => kit = VaultTestKit());

    testWidgets('follows the properties, retries an upload, refreshes', (
      tester,
    ) async {
      final properties = MockSellerPropertiesCubit();
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
        Stream.fromIterable([changed]),
        initialState: const SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [sentProperty],
        ),
      );
      kit.documents = [
        document('a', kind: DocumentKind.dpe, status: DocumentStatus.analyzing),
      ];
      when(() => kit.picker.pick(any())).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List.fromList([1]),
          name: 'x.pdf',
          path: 'x.pdf',
        ),
      );
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
      await kit.pump(
        tester,
        VaultDocumentsPage(
          target: const VaultTarget.property('property-id'),
          rubric: VaultRubric.tax,
          services: kit.services,
        ),
        propertiesCubit: properties,
        height: 1400,
      );
      verify(() => kit.repository.getDocumentsOf(['property-id'])).called(2);
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();
      expect(find.text('L’envoi de « x.pdf » a échoué.'), findsOneWidget);
      await tester.fling(
        find.text('Mes documents'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      verify(() => kit.repository.getDocumentsOf(['property-id'])).called(1);
    });

    testWidgets('adds the identity document of a chosen owner', (tester) async {
      kit.documents = [
        document('a', kind: DocumentKind.titleDeed),
        document(
          'b',
          kind: DocumentKind.identityDocument,
          status: DocumentStatus.analyzing,
        ),
        document('c'),
      ];
      when(() => kit.picker.pick(any())).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List.fromList([1]),
          name: 'id.pdf',
          path: 'id.pdf',
        ),
      );
      kit.uploads(document('id', kind: DocumentKind.identityDocument));
      await kit.pump(
        tester,
        VaultDocumentsPage(
          target: const VaultTarget.property('property-id'),
          rubric: VaultRubric.identity,
          services: kit.services,
        ),
        height: 1400,
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('La pièce d’identité de qui ?'), findsOneWidget);
      await tester.tap(find.text('Marc Durand'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();
      verify(
        () => kit.repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: DocumentKind.identityDocument,
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
          title: any(named: 'title'),
          ownerRef: 'owner-2',
        ),
      ).called(1);
      // One owner: no question; the owner sheet can be dismissed.
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Fichiers'), findsNothing);
    });

    testWidgets('one owner is chosen by itself; a dismissed kind stops', (
      tester,
    ) async {
      kit.owners = const [sophie];
      await kit.pump(
        tester,
        VaultDocumentsPage(
          target: const VaultTarget.property('property-id'),
          rubric: VaultRubric.identity,
          services: kit.services,
        ),
        height: 1400,
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('Fichiers'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Ajouter un document'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Fichiers'), findsNothing);
    });

    testWidgets('reuses a document of another property', (tester) async {
      when(() => kit.repository.getDocuments('draft-id')).thenAnswer(
        (_) async => [
          document(
            'tax',
            propertyId: 'draft-id',
            kind: DocumentKind.propertyTax,
          ),
        ],
      );
      when(
        () => kit.repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer(
        (_) async => document('copy', kind: DocumentKind.propertyTax),
      );
      await kit.pump(
        tester,
        VaultDocumentsPage(
          target: const VaultTarget.property('property-id'),
          rubric: VaultRubric.tax,
          services: kit.services,
        ),
        properties: const [sentProperty, draftProperty],
        height: 1400,
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Depuis un autre bien'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tax.pdf'));
      await tester.pumpAndSettle();
      verify(
        () => kit.repository.copyDocument(
          any(),
          ownerId: 'user-id',
          toPropertyId: 'property-id',
        ),
      ).called(1);
      // Dismissed: nothing copied.
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Depuis un autre bien'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      verifyNoMoreInteractions(kit.picker);
    });

    testWidgets('turns the notary sharing on', (tester) async {
      kit.documents = [document('a', kind: DocumentKind.dpe)];
      when(() => kit.repository.setDocumentVisibility(any(), any()))
          .thenAnswer((_) async => {DocumentVisibility.notary});
      await kit.pump(
        tester,
        VaultDocumentsPage(
          target: const VaultTarget.property('property-id'),
          rubric: VaultRubric.energy,
          services: kit.services,
        ),
        height: 1600,
      );
      await tester.tap(find.text('DPE'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      verify(
        () => kit.repository.setDocumentVisibility('a', {
          DocumentVisibility.notary,
        }),
      ).called(1);
    });
  });

  testWidgets('C1 searches a lot with the property of each document', (
    tester,
  ) async {
    final kit = VaultTestKit()
      ..documents = [
        document('a', kind: DocumentKind.dpe, propertyId: 'draft-id'),
      ];
    const lot = PropertyLot(id: 'lot-id', ownerId: 'user-id', name: 'Lot');
    await kit.pump(
      tester,
      VaultPage(services: kit.services),
      properties: const [
        Property(id: 'property-id', ownerId: 'user-id', lotId: 'lot-id'),
        Property(
          id: 'draft-id',
          ownerId: 'user-id',
          lotId: 'lot-id',
          addressCity: 'Lyon',
        ),
      ],
      lots: const [lot],
    );
    await tester.tap(
      find.descendant(
        of: find.byType(VaultTargetSelector),
        matching: find.byType(Text),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lot'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lyon');
    await tester.pumpAndSettle();
    expect(find.text('1 résultat'.toUpperCase()), findsOneWidget);
  });
}

extension on PropertyOwner {
  /// An owner without a name.
  PropertyOwner copyWithName() => PropertyOwner(
    id: id,
    propertyId: propertyId,
    position: position,
    firstName: '',
    lastName: '',
  );
}
