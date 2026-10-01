import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/models/document_checklist.dart';
import 'package:property_repository/property_repository.dart';

PropertyDocument _document(
  DocumentKind kind, {
  String? id,
  DocumentStatus status = DocumentStatus.received,
}) => PropertyDocument(
  id: id ?? kind.value,
  propertyId: 'property-id',
  kind: kind,
  storagePath: 'user-id/property-id/${id ?? kind.value}.pdf',
  status: status,
);

const _empty = Property(id: 'property-id', ownerId: 'user-id');

const _complete = Property(
  id: 'property-id',
  ownerId: 'user-id',
  addressLabel: '1 rue de la Paix',
  parcelConfirmed: true,
  propertyType: PropertyType.house,
  purchaseYear: 2012,
  constructionYear: 1998,
  livingAreaM2: 115,
  roomsCount: 5,
  heatingEnergy: HeatingEnergy.heatPump,
  sanitation: Sanitation.mainsSewer,
  measurementMethod: MeasurementMethod.manual,
  noiseLevel: 3,
);

void main() {
  group(DocumentChecklist, () {
    test('lists the expected kinds, missing or optional, with no file', () {
      final checklist = DocumentChecklist.of(_empty, const []);

      expect(
        checklist.rows.map((row) => row.kind),
        DocumentChecklist.listedKinds,
      );
      expect(
        {for (final row in checklist.rows) row.kind: row.status},
        {
          DocumentKind.titleDeed: DocumentRowStatus.missing,
          DocumentKind.propertyTax: DocumentRowStatus.missing,
          DocumentKind.energyBills: DocumentRowStatus.optional,
          DocumentKind.worksInvoice: DocumentRowStatus.optional,
          DocumentKind.identityDocument: DocumentRowStatus.missing,
          DocumentKind.diagnostics: DocumentRowStatus.missing,
          DocumentKind.sanitationReport: DocumentRowStatus.optional,
        },
      );
      expect(checklist.sanitationRule, SanitationReportRule.unknown);
      expect(checklist.missingCount, 4);
      expect(checklist.score, 0);
      expect(checklist.nextBestKind, DocumentKind.titleDeed);
    });

    test('requires the SPANC report for individual sanitation', () {
      for (final sanitation in [Sanitation.septicTank, Sanitation.soakaway]) {
        final checklist = DocumentChecklist.of(
          Property(id: 'p', ownerId: 'u', sanitation: sanitation),
          const [],
        );
        final spanc = checklist.rows.last;
        expect(checklist.sanitationRule, SanitationReportRule.required);
        expect(spanc.kind, DocumentKind.sanitationReport);
        expect(spanc.isRequired, isTrue);
        expect(spanc.status, DocumentRowStatus.missing);
        expect(checklist.missingCount, 5);
      }
    });

    test('an optional SPANC report can only raise the score', () {
      final without = DocumentChecklist.of(_empty, [
        _document(DocumentKind.titleDeed),
      ]);
      final withReport = DocumentChecklist.of(_empty, [
        _document(DocumentKind.titleDeed),
        _document(DocumentKind.sanitationReport),
      ]);

      // 20/80 of 70 (the report is not expected) vs 30/90 of 70.
      expect(without.score, 18);
      expect(withReport.score, 23);
      expect(without.nextBestKind, DocumentKind.diagnostics);
    });

    test('marks the SPANC report not concerned when on the sewer', () {
      final checklist = DocumentChecklist.of(_complete, const []);

      expect(checklist.sanitationRule, SanitationReportRule.mainsSewer);
      expect(checklist.rows.last.status, DocumentRowStatus.notConcerned);
      // Answers only: 30 points.
      expect(checklist.score, 30);
    });

    test('computes the statuses of the provided kinds', () {
      final checklist = DocumentChecklist.of(_complete, [
        _document(DocumentKind.titleDeed, status: DocumentStatus.analyzed),
        _document(DocumentKind.propertyTax, status: DocumentStatus.analyzed),
        _document(DocumentKind.energyBills, id: 'e1'),
        _document(
          DocumentKind.energyBills,
          id: 'e2',
          status: DocumentStatus.analyzing,
        ),
        _document(DocumentKind.worksInvoice),
        _document(
          DocumentKind.identityDocument,
          status: DocumentStatus.rejected,
        ),
        _document(DocumentKind.plan),
      ]);

      expect(
        {for (final row in checklist.rows) row.kind: row.status},
        {
          DocumentKind.titleDeed: DocumentRowStatus.analyzed,
          DocumentKind.propertyTax: DocumentRowStatus.analyzed,
          DocumentKind.energyBills: DocumentRowStatus.analyzing,
          DocumentKind.worksInvoice: DocumentRowStatus.received,
          DocumentKind.identityDocument: DocumentRowStatus.rejected,
          DocumentKind.diagnostics: DocumentRowStatus.missing,
          DocumentKind.sanitationReport: DocumentRowStatus.notConcerned,
          DocumentKind.plan: DocumentRowStatus.received,
        },
      );
      expect(checklist.rows[2].documents, hasLength(2));
      expect(checklist.missingCount, 2);
      // Documents 45/80 of 70 + answers 30 = 69.
      expect(checklist.score, 69);
      expect(checklist.nextBestKind, DocumentKind.diagnostics);
    });

    test('scores 100 with everything provided', () {
      final checklist = DocumentChecklist.of(_complete, [
        for (final kind in DocumentChecklist.listedKinds) _document(kind),
      ]);

      expect(checklist.missingCount, 0);
      expect(checklist.score, 100);
      expect(checklist.nextBestKind, isNull);
    });

    test('row status tells whether files were provided', () {
      expect(DocumentRowStatus.missing.isProvided, isFalse);
      expect(DocumentRowStatus.rejected.isProvided, isFalse);
      expect(DocumentRowStatus.received.isProvided, isTrue);
      expect(DocumentRowStatus.analyzed.isProvided, isTrue);
    });

    test('supports value equality', () {
      expect(
        DocumentChecklist.of(_empty, const []),
        DocumentChecklist.of(_empty, const []),
      );
      expect(
        const DocumentRow(
          kind: DocumentKind.plan,
          status: DocumentRowStatus.optional,
          isRequired: false,
        ),
        const DocumentRow(
          kind: DocumentKind.plan,
          status: DocumentRowStatus.optional,
          isRequired: false,
        ),
      );
    });
  });
}
