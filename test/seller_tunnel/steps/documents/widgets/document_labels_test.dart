import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/models/document_checklist.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

const _nbsp = ' ';

void main() {
  final l10n = AppLocalizationsFr();

  group('DocumentLabels', () {
    test('names every kind, alone and in a sentence', () {
      expect(
        [for (final kind in DocumentKind.values) l10n.documentKind(kind)],
        [
          'Titre de propriété',
          'Taxe foncière',
          'Factures d’énergie',
          'Factures de travaux',
          'Pièce d’identité',
          'Diagnostics',
          'Rapport SPANC',
          'Plan',
          'Autre document',
          'DPE',
          'Contrat d’entretien',
          'Assurance',
          'Copropriété (règlement, PV d’AG)',
        ],
      );
      expect(
        [
          for (final kind in DocumentKind.values)
            l10n.documentKindInSentence(kind),
        ],
        [
          'votre titre de propriété',
          'votre dernier avis de taxe foncière',
          'vos factures d’énergie',
          'vos factures de travaux',
          'votre pièce d’identité',
          'vos diagnostics',
          'votre rapport SPANC',
          'plan',
          'autre document',
          'DPE',
          'contrat d’entretien',
          'assurance',
          'copropriété (règlement, pv d’ag)',
        ],
      );
    });

    test('describes what is expected for a kind with no file', () {
      String subtitle(
        DocumentKind kind, [
        SanitationReportRule rule = SanitationReportRule.unknown,
      ]) => l10n.documentRowSubtitle(
        DocumentRow(
          kind: kind,
          status: DocumentRowStatus.optional,
          isRequired: false,
        ),
        rule,
      );

      expect(
        subtitle(DocumentKind.titleDeed),
        'Acte notarié de votre acquisition',
      );
      expect(
        subtitle(DocumentKind.propertyTax),
        'Dernier avis de taxe foncière',
      );
      expect(
        subtitle(DocumentKind.energyBills),
        'Électricité, gaz, fioul… sur 12 mois',
      );
      expect(
        subtitle(DocumentKind.worksInvoice),
        'Rénovations, équipements, garanties',
      );
      expect(subtitle(DocumentKind.plan), 'Plans du bien');
      expect(subtitle(DocumentKind.other), 'Autres justificatifs');
      for (final kind in [
        DocumentKind.dpe,
        DocumentKind.maintenanceContract,
        DocumentKind.insurance,
        DocumentKind.coOwnership,
      ]) {
        expect(subtitle(kind), 'Autres justificatifs');
      }
      expect(
        subtitle(DocumentKind.sanitationReport),
        'Si vous n’êtes pas raccordé au tout-à-l’égout',
      );
      expect(
        subtitle(DocumentKind.sanitationReport, SanitationReportRule.required),
        'Obligatoire en assainissement individuel',
      );
    });

    test('describes the files of a kind', () {
      String subtitle(DocumentRowStatus status) => l10n.documentRowSubtitle(
        DocumentRow(
          kind: DocumentKind.plan,
          status: status,
          isRequired: false,
          documents: const [
            PropertyDocument(
              id: 'd',
              propertyId: 'p',
              kind: DocumentKind.plan,
              storagePath: 'u/p/d',
            ),
          ],
        ),
        SanitationReportRule.unknown,
      );

      expect(subtitle(DocumentRowStatus.rejected), '1 fichier · à renvoyer');
      expect(subtitle(DocumentRowStatus.analyzed), '1 fichier · analysé');
    });

    test('formats sizes', () {
      expect(l10n.documentSize(0), '1${_nbsp}Ko');
      expect(l10n.documentSize(345 * 1024), '345${_nbsp}Ko');
      expect(l10n.documentSize(1024 * 1024 - 1), '1${_nbsp}023${_nbsp}Ko');
      expect(l10n.documentSize(20 * 1024 * 1024), '20,0${_nbsp}Mo');
    });
  });

  test('documentDate formats a day', () {
    expect(documentDate(DateTime(2026, 1, 5)), '05/01/2026');
  });

  test('documentStatusBadge and documentStatusTone cover every status', () {
    final badges = {
      for (final status in DocumentRowStatus.values)
        status: documentStatusBadge(l10n, status),
    };
    expect(badges[DocumentRowStatus.rejected]!.label, 'À renvoyer');
    expect(
      badges[DocumentRowStatus.rejected]!.variant,
      RealestyBadgeVariant.missing,
    );
    expect(badges[DocumentRowStatus.optional]!.label, 'Facultatif');
    expect(
      documentStatusTone(DocumentRowStatus.rejected),
      RealestyListTileTone.error,
    );
    expect(
      documentStatusTone(DocumentRowStatus.analyzed),
      RealestyListTileTone.success,
    );
    expect(
      documentStatusTone(DocumentRowStatus.optional),
      RealestyListTileTone.neutral,
    );
  });
}
