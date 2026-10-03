import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/models/document_checklist.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Copy of the document vault.
extension DocumentLabels on AppLocalizations {
  /// Name of a kind of document ("Titre de propriété").
  String documentKind(DocumentKind kind) => switch (kind) {
    DocumentKind.titleDeed => documentsKindTitleDeed,
    DocumentKind.propertyTax => documentsKindPropertyTax,
    DocumentKind.energyBills => documentsKindEnergyBills,
    DocumentKind.worksInvoice => documentsKindWorksInvoice,
    DocumentKind.identityDocument => documentsKindIdentity,
    DocumentKind.diagnostics => documentsKindDiagnostics,
    DocumentKind.sanitationReport => documentsKindSanitationReport,
    DocumentKind.plan => documentsKindPlan,
    DocumentKind.other => documentsKindOther,
    DocumentKind.dpe => vaultKindDpe,
    DocumentKind.maintenanceContract => vaultKindMaintenanceContract,
    DocumentKind.insurance => vaultKindInsurance,
    DocumentKind.coOwnership => vaultKindCoOwnership,
  };

  /// The kind inside a sentence ("votre titre de propriété").
  String documentKindInSentence(DocumentKind kind) => switch (kind) {
    DocumentKind.titleDeed => documentsHintTitleDeed,
    DocumentKind.propertyTax => documentsHintPropertyTax,
    DocumentKind.energyBills => documentsHintEnergyBills,
    DocumentKind.worksInvoice => documentsHintWorksInvoice,
    DocumentKind.identityDocument => documentsHintIdentity,
    DocumentKind.diagnostics => documentsHintDiagnostics,
    DocumentKind.sanitationReport => documentsHintSanitationReport,
    DocumentKind.plan => documentsKindPlan.toLowerCase(),
    DocumentKind.other => documentsKindOther.toLowerCase(),
    DocumentKind.dpe => vaultKindDpe,
    DocumentKind.maintenanceContract ||
    DocumentKind.insurance ||
    DocumentKind.coOwnership => documentKind(kind).toLowerCase(),
  };

  /// Subtitle of a row: what is expected, or the files and their status.
  String documentRowSubtitle(DocumentRow row, SanitationReportRule rule) {
    final status = switch (row.status) {
      DocumentRowStatus.received => documentsStatusReceived,
      DocumentRowStatus.analyzing => documentsStatusAnalyzing,
      DocumentRowStatus.analyzed => documentsStatusAnalyzed,
      DocumentRowStatus.rejected => documentsStatusRejected,
      DocumentRowStatus.missing ||
      DocumentRowStatus.optional ||
      DocumentRowStatus.notConcerned => null,
    };
    if (status != null) {
      return '${documentsFileCount(row.documents.length)} · $status';
    }
    return switch (row.kind) {
      DocumentKind.titleDeed => documentsSubtitleTitleDeed,
      DocumentKind.propertyTax => documentsSubtitlePropertyTax,
      DocumentKind.energyBills => documentsSubtitleEnergyBills,
      DocumentKind.worksInvoice => documentsSubtitleWorksInvoice,
      DocumentKind.identityDocument => documentsSubtitleIdentity,
      DocumentKind.diagnostics => documentsSubtitleDiagnostics,
      DocumentKind.sanitationReport => switch (rule) {
        SanitationReportRule.required => documentsSubtitleSanitationRequired,
        SanitationReportRule.mainsSewer =>
          documentsSubtitleSanitationMainsSewer,
        SanitationReportRule.unknown => documentsSubtitleSanitationUnknown,
      },
      DocumentKind.plan => documentsSubtitlePlan,
      DocumentKind.other ||
      DocumentKind.dpe ||
      DocumentKind.maintenanceContract ||
      DocumentKind.insurance ||
      DocumentKind.coOwnership => documentsSubtitleOther,
    };
  }

  /// "1,2 Mo", "340 Ko".
  String documentSize(int bytes) {
    const kilobyte = 1024;
    const megabyte = kilobyte * 1024;
    if (bytes >= megabyte) {
      return documentsSizeMegabytes(
        frenchNumber(bytes / megabyte, decimalDigits: 1),
      );
    }
    return documentsSizeKilobytes(
      frenchNumber((bytes / kilobyte).ceil().clamp(1, 1023)),
    );
  }
}

/// Badge of a row status.
RealestyBadge documentStatusBadge(
  AppLocalizations l10n,
  DocumentRowStatus status,
) => switch (status) {
  DocumentRowStatus.missing => RealestyBadge(
    label: l10n.documentsBadgeMissing,
    variant: RealestyBadgeVariant.missing,
  ),
  DocumentRowStatus.optional => RealestyBadge(
    label: l10n.documentsBadgeOptional,
  ),
  DocumentRowStatus.notConcerned => RealestyBadge(
    label: l10n.documentsBadgeNotConcerned,
  ),
  DocumentRowStatus.rejected => RealestyBadge(
    label: l10n.documentsBadgeRejected,
    variant: RealestyBadgeVariant.missing,
  ),
  DocumentRowStatus.received => RealestyBadge(
    label: l10n.documentsBadgeReceived,
  ),
  DocumentRowStatus.analyzing => RealestyBadge(
    label: l10n.documentsBadgeAnalyzing,
    variant: RealestyBadgeVariant.toComplete,
    icon: RealestyIcons.clock,
  ),
  DocumentRowStatus.analyzed => RealestyBadge(
    label: l10n.documentsBadgeAnalyzed,
    variant: RealestyBadgeVariant.certified,
  ),
};

/// Tone of the icon tile of a row status.
RealestyListTileTone documentStatusTone(DocumentRowStatus status) =>
    switch (status) {
      DocumentRowStatus.missing ||
      DocumentRowStatus.rejected => RealestyListTileTone.error,
      DocumentRowStatus.analyzed => RealestyListTileTone.success,
      DocumentRowStatus.optional ||
      DocumentRowStatus.notConcerned ||
      DocumentRowStatus.received ||
      DocumentRowStatus.analyzing => RealestyListTileTone.neutral,
    };

/// "01/10/2026".
String documentDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
