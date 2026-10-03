import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:property_repository/property_repository.dart';

import '../../fixtures.dart';
import '../vault_fixtures.dart';

void main() {
  group(VaultDocumentStatus, () {
    test('of a document', () {
      expect(
        VaultDocumentStatus.of(document('a')),
        VaultDocumentStatus.received,
      );
      expect(
        VaultDocumentStatus.of(document('a', status: DocumentStatus.analyzing)),
        VaultDocumentStatus.analyzing,
      );
      expect(
        VaultDocumentStatus.of(document('a', status: DocumentStatus.analyzed)),
        VaultDocumentStatus.analyzed,
      );
      expect(
        VaultDocumentStatus.of(document('a', verifiedAt: DateTime(2026))),
        VaultDocumentStatus.verified,
      );
      expect(
        VaultDocumentStatus.of(
          document(
            'a',
            status: DocumentStatus.rejected,
            verifiedAt: DateTime(2026),
          ),
        ),
        VaultDocumentStatus.toReplace,
      );
    });
  });

  group(VaultDocumentEntry, () {
    test('allows any change in a draft', () {
      final entry = VaultDocumentEntry(
        property: draftProperty,
        document: document('a', propertyId: 'draft-id'),
      );
      expect(entry.canDelete, isTrue);
      expect(entry.canReplace, isTrue);
      expect(entry.canShare, isTrue);
    });

    test('locks the documents of a sent dossier', () {
      final entry = VaultDocumentEntry(
        property: sentProperty,
        document: document('a', kind: DocumentKind.identityDocument),
      );
      expect(entry.canDelete, isFalse);
      expect(entry.canReplace, isFalse);
      expect(entry.canShare, isFalse);
      expect(
        entry,
        isNot(
          equals(
            VaultDocumentEntry(property: sentProperty, document: document('b')),
          ),
        ),
      );
    });

    test('lets an unverified addition go, a rejected one be replaced', () {
      expect(
        VaultDocumentEntry(
          property: sentProperty,
          document: document('a', added: true),
        ).canDelete,
        isTrue,
      );
      expect(
        VaultDocumentEntry(
          property: sentProperty,
          document: document('a', added: true, verifiedAt: DateTime(2026)),
        ).canDelete,
        isFalse,
      );
      final rejected = VaultDocumentEntry(
        property: sentProperty,
        document: document('a', status: DocumentStatus.rejected),
      );
      expect(rejected.canDelete, isFalse);
      expect(rejected.canReplace, isTrue);
    });
  });

  group(VaultContents, () {
    test('files the documents by rubric, newest first in the recents', () {
      final contents = VaultContents.of(
        properties: const [sentProperty],
        documents: [
          document(
            'deed',
            kind: DocumentKind.titleDeed,
            verifiedAt: DateTime(2026),
            uploadedAt: DateTime(2026, 9),
          ),
          document(
            'dpe',
            kind: DocumentKind.dpe,
            status: DocumentStatus.analyzing,
            uploadedAt: DateTime(2026, 9, 20),
          ),
          document(
            'tax',
            kind: DocumentKind.propertyTax,
            status: DocumentStatus.rejected,
            uploadedAt: DateTime(2026, 9, 10),
          ),
          document('old', replacedBy: 'dpe'),
          document('other-property', propertyId: 'nope'),
        ],
        owners: const {
          'property-id': [sophie, marc],
        },
        valuations: {'property-id': testValuation},
      );
      expect(contents.documentCount, 4);
      expect(contents.section(VaultRubric.property).verifiedCount, 1);
      expect(contents.section(VaultRubric.energy).analyzingCount, 1);
      expect(contents.section(VaultRubric.tax).toReplaceCount, 1);
      expect(contents.section(VaultRubric.mandates).count, 1);
      expect(contents.section(VaultRubric.mandates).verifiedCount, 1);
      expect(contents.toReplace.single.document.id, 'tax');
      expect(
        [
          for (final entry in contents.recents)
            switch (entry) {
              VaultDocumentEntry(:final document) => document.id,
              VaultValuationEntry() => 'valuation',
              VaultMissingEntry() => 'missing',
            },
        ],
        ['valuation', 'dpe', 'tax'],
      );
      // Both owners miss their identity document; the deed is there.
      expect(
        [for (final entry in contents.missing) entry.owner?.firstName],
        ['Sophie', 'Marc'],
      );
      expect(contents.section(VaultRubric.identity).missing, hasLength(2));
      expect(contents, equals(contents));
      expect(contents.sections.first, equals(contents.sections.first));
    });

    test('a document for no owner covers the first owner without one', () {
      final contents = VaultContents.of(
        properties: const [sentProperty],
        documents: [
          document('deed', kind: DocumentKind.titleDeed),
          document(
            'id-marc',
            kind: DocumentKind.identityDocument,
            ownerRef: 'owner-2',
          ),
          document('id', kind: DocumentKind.identityDocument),
        ],
        owners: const {
          'property-id': [marc, sophie],
        },
      );
      expect(contents.missing, isEmpty);
    });

    test('without owners: the title deed and one identity document', () {
      final missing = VaultContents.of(
        properties: const [draftProperty],
        documents: const [],
      ).missing;
      expect(
        [for (final entry in missing) entry.kind],
        [DocumentKind.titleDeed, DocumentKind.identityDocument],
      );
      expect(missing.last.owner, isNull);
      expect(missing.first, equals(missing.first));
      expect(
        VaultContents.of(
          properties: const [draftProperty],
          documents: [
            document(
              'id',
              propertyId: 'draft-id',
              kind: DocumentKind.identityDocument,
            ),
          ],
        ).missing.single.kind,
        DocumentKind.titleDeed,
      );
    });

    test('searches without case nor accents', () {
      final contents = VaultContents.of(
        properties: const [sentProperty],
        documents: [
          document(
            'a',
            kind: DocumentKind.propertyTax,
            title: 'Taxe foncière 2025',
          ),
          document('b', kind: DocumentKind.dpe, title: 'DPE'),
        ],
      );
      String label(VaultDocumentEntry entry) => entry.document.title!;
      expect(contents.search('FONCIERE', label).single.document.id, 'a');
      expect(contents.search('  ', label), isEmpty);
      expect(contents.search('zzz', label), isEmpty);
    });

    test('valuations and missing entries compare by value', () {
      final valuation = VaultValuationEntry(
        property: sentProperty,
        valuation: testValuation,
      );
      expect(
        valuation,
        VaultValuationEntry(property: sentProperty, valuation: testValuation),
      );
    });
  });
}
