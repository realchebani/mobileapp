import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/vault/models/vault_contents.dart';
import 'package:mobileapp/seller_space/vault/models/vault_rubric.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Copy of the vault (C1, V18).
extension VaultLabels on AppLocalizations {
  /// "Propriété", "Énergie"…
  String vaultRubric(VaultRubric rubric) => switch (rubric) {
    VaultRubric.property => vaultRubricProperty,
    VaultRubric.tax => vaultRubricTax,
    VaultRubric.energy => vaultRubricEnergy,
    VaultRubric.works => vaultRubricWorks,
    VaultRubric.identity => vaultRubricIdentity,
    VaultRubric.mandates => vaultRubricMandates,
    VaultRubric.other => vaultRubricOther,
  };

  /// Icon of a rubric.
  static RealestyIcons rubricIcon(VaultRubric rubric) => switch (rubric) {
    VaultRubric.property => RealestyIcons.home,
    VaultRubric.tax => RealestyIcons.euro,
    VaultRubric.energy => RealestyIcons.spark,
    VaultRubric.works => RealestyIcons.briefcase,
    VaultRubric.identity => RealestyIcons.user,
    VaultRubric.mandates => RealestyIcons.pen,
    VaultRubric.other => RealestyIcons.file,
  };

  /// Label of an extracted information [key] (`classe` → « Classe
  /// énergie »); an unknown key is shown readable (`date_pose` → « Date
  /// pose »).
  String vaultExtractedLabel(String key) => switch (key) {
    'classe' => vaultExtractedClasse,
    'annee' => vaultExtractedAnnee,
    'montant' => vaultExtractedMontant,
    'entreprise' => vaultExtractedEntreprise,
    'equipement' => vaultExtractedEquipement,
    'date' => vaultExtractedDate,
    'surface' => vaultExtractedSurface,
    'garantie' => vaultExtractedGarantie,
    _ => _readable(key),
  };

  static String _readable(String key) {
    final text = key.replaceAll('_', ' ').trim();
    return text.isEmpty ? key : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  /// Name of a kind of document.
  String vaultKind(DocumentKind kind) => documentKind(kind);

  /// The title of a document: the seller's, else its kind (with the
  /// owner of an identity document).
  String vaultDocumentTitle(PropertyDocument document, {PropertyOwner? owner}) {
    final title = document.title;
    if (title != null && title.trim().isNotEmpty) return title;
    final kind = vaultKind(document.kind);
    if (owner == null) return kind;
    final name = '${owner.firstName} ${owner.lastName}'.trim();
    return name.isEmpty ? kind : vaultOwnerDocument(kind, name);
  }

  /// "PDF · 340 Ko · ajouté le 12/09/2026".
  String vaultDocumentDetails(PropertyDocument document) {
    final type = switch (document.mimeType) {
      'application/pdf' => 'PDF',
      final String mime when mime.startsWith('image/') => vaultFileImage,
      _ => null,
    };
    final size = document.sizeBytes;
    final date = document.uploadedAt;
    return [
      ?type,
      if (size != null) documentSize(size),
      if (date != null) vaultAddedOn(documentDate(date)),
    ].join(' · ');
  }

  /// "Privé", "Acquéreurs", "Notaire", "Acquéreurs · Notaire".
  String vaultVisibility(Set<DocumentVisibility> visibility) {
    if (visibility.isEmpty) return vaultVisibilityPrivate;
    return [
      if (visibility.contains(DocumentVisibility.buyers)) vaultVisibilityBuyers,
      if (visibility.contains(DocumentVisibility.notary)) vaultVisibilityNotary,
    ].join(' · ');
  }

  /// Badge of a document status.
  RealestyBadge vaultStatusBadge(VaultDocumentStatus status) =>
      switch (status) {
        VaultDocumentStatus.received => RealestyBadge(
          label: documentsBadgeReceived,
        ),
        VaultDocumentStatus.analyzing => RealestyBadge(
          label: documentsBadgeAnalyzing,
          variant: RealestyBadgeVariant.toComplete,
          icon: RealestyIcons.clock,
        ),
        VaultDocumentStatus.analyzed => RealestyBadge(
          label: documentsBadgeAnalyzed,
          variant: RealestyBadgeVariant.certified,
        ),
        VaultDocumentStatus.verified => RealestyBadge(
          label: vaultBadgeVerified,
          variant: RealestyBadgeVariant.certified,
          icon: RealestyIcons.shield,
        ),
        VaultDocumentStatus.toReplace => RealestyBadge(
          label: vaultBadgeToReplace,
          variant: RealestyBadgeVariant.missing,
        ),
      };

  /// Summary of a rubric: "3 documents · tous vérifiés", "2 à ajouter".
  String vaultSectionSummary(VaultSection section) {
    final parts = <String>[
      if (section.count > 0 || section.missing.isEmpty)
        vaultDocumentCount(section.count),
      if (section.missing.isNotEmpty) vaultToAdd(section.missing.length),
      if (section.toReplaceCount > 0) vaultToReplace(section.toReplaceCount),
      if (section.analyzingCount > 0) vaultAnalyzing(section.analyzingCount),
      if (section.count > 0 &&
          section.verifiedCount == section.count &&
          section.missing.isEmpty)
        vaultAllVerified,
    ];
    return parts.join(' · ');
  }
}
