import 'package:realesty_backoffice/l10n/l10n.dart';

/// French label of `property_documents.kind`.
String documentKindLabel(AppLocalizations l10n, String kind) => switch (kind) {
  'titre_propriete' => l10n.kindTitrePropriete,
  'taxe_fonciere' => l10n.kindTaxeFonciere,
  'facture_energie' => l10n.kindFactureEnergie,
  'facture_travaux' => l10n.kindFactureTravaux,
  'piece_identite' => l10n.kindPieceIdentite,
  'diagnostics' => l10n.kindDiagnostics,
  'rapport_spanc' => l10n.kindRapportSpanc,
  'plan' => l10n.kindPlan,
  'dpe' => l10n.kindDpe,
  'contrat_entretien' => l10n.kindContratEntretien,
  'assurance' => l10n.kindAssurance,
  'copropriete' => l10n.kindCopropriete,
  _ => l10n.kindAutre,
};

/// Tunnel steps of the fill sheet and the voice thread, in order.
const tunnelSteps = ['location', 'context', 'technical', 'rooms', 'lifestyle'];

String stepLabel(AppLocalizations l10n, String step) => switch (step) {
  'location' => l10n.stepLocation,
  'context' => l10n.stepContext,
  'technical' => l10n.stepTechnical,
  'rooms' => l10n.stepRooms,
  'lifestyle' => l10n.stepLifestyle,
  _ => step,
};

/// French label of a fill sheet `source`.
String? sourceLabel(AppLocalizations l10n, String? source) => switch (source) {
  'dicte' => l10n.sourceDicte,
  'dicte_autre_etape' => l10n.sourceDicteAutreEtape,
  'saisi' => l10n.sourceSaisi,
  'extrait' => l10n.sourceExtrait,
  'externe' => l10n.sourceExterne,
  'non_trace' => l10n.sourceNonTrace,
  'invalide' => l10n.sourceInvalide,
  _ => null,
};
