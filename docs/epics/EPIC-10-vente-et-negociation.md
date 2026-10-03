# EPIC-10 · Commercialisation, négociation & suivi de la vente

**Objectif** : après la mise en ligne, le vendeur suit l’activité de son annonce (V12b en 1 %, V15 en L’Expert), répond aux offres (accepter, refuser, contre-proposer) et suit sa vente jusqu’à l’acte authentique (V17).
**Statut** : 📋 À faire (plan rédigé, aucun code)

Plan : [Vente & négociation](../plans/2026-10-03-vente-et-negociation.md). Spec d’origine : [Parcours vendeur V8b → V19](../plans/2026-10-01-parcours-vendeur-v8b-v19.md) (§3 V12b, V15, V16, V17, §4.5, §6 EPIC-10). Plan frère : [Visites](../plans/2026-10-03-visites.md) (EPIC-09). Runbook équipe : [Suivre une vente](../runbooks/suivre-une-vente.md) (EPIC-08, à compléter).

Décisions applicables : **pas d’app acquéreur, d’agences ni de notaire connectés en v1** (offres, réponses des acquéreurs, jalons, interlocuteurs et documents saisis par l’équipe via des fonctions `staff_*`, démo marquée, tout en `is_test`) ; **aucun paiement** (commission affichée à titre indicatif) ; mandat de test, montage juridique à valider avant tout vrai vendeur ; notifications in-app seulement ; un lot se vend en entier ou bien par bien ; V12b déplacé ici depuis EPIC-09.

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-10.1 · Tableau de bord de vente (V12b) 📋
*En tant que vendeur 1 %, je veux suivre l’activité de mon annonce.*
- 📋 Période 7 j / 30 j / depuis la mise en ligne ; demandes de visite, visites réalisées et à venir, offres reçues.
- 📋 Vues et favoris masqués tant que l’app acquéreur n’existe pas ; diffusion « Realesty · En ligne ».
- 📋 Offre à examiner → V16 ; prochaines visites → V13 ; retours des visiteurs → compte rendu (V14).

## US-10.2 · Ma vente avec L’Expert (V15) 📋
*En tant que vendeur 3 %, je veux voir mon agent, l’activité et les offres.*
- 📋 Carte de l’agent (Appeler / Message) ou « Un agent vous contacte sous 24 h ».
- 📋 Compteurs, bandeau « offre à examiner », fil d’activité daté, dernier compte rendu.

## US-10.3 · Recevoir une offre 📋
*En tant que vendeur, je veux être prévenu d’une offre et la lire en détail.*
- 📋 Notification in-app ; montant et écart au prix affiché, financement, condition suspensive, date de signature souhaitée, validité.
- 📋 Conseil de l’agent en L’Expert ; visite et compte rendu liés.

## US-10.4 · Accepter ou refuser une offre 📋
*En tant que vendeur, je veux accepter ou refuser une offre.*
- 📋 Acceptation avec confirmation intégrée ; les autres offres en attente sont refusées ; la vente passe « Sous offre » et l’annonce est figée.
- 📋 Refus avec motif et message facultatifs.
- 📋 Phase de test : bandeau « offre fictive, sans valeur juridique ».

## US-10.5 · Contre-proposer 📋
*En tant que vendeur, je veux faire une contre-proposition.*
- 📋 Montant borné entre l’offre et le prix affiché, message facultatif de 500 caractères.
- 📋 Une seule proposition en attente par négociation, retrait possible ; expiration après 7 jours ; historique horodaté.

## US-10.6 · Suivre la vente jusqu’à l’acte (V17) 📋
*En tant que vendeur, je veux suivre les étapes jusqu’à l’acte authentique.*
- 📋 Prix de vente et commission indicative ; étapes offre acceptée, compromis, rétractation, condition de prêt, acte.
- 📋 Copie du compromis ; notaire (et agent en L’Expert) ; notification à chaque étape ; état « Vendu ».

## US-10.7 · Annulation d’une vente en cours 📋
*En tant que vendeur, je veux savoir ce qui se passe si l’acquéreur se rétracte ou n’obtient pas son prêt.*
- 📋 L’équipe enregistre l’annulation : offre « annulée », vente remise en ligne, notification.
- 📋 Pas de retrait de la vente par le vendeur après une acceptation (« Contactez votre conseiller »).

## US-10.8 · Retrouver mes offres et documents 📋
*En tant que vendeur, je veux retrouver toutes mes offres et les documents de ma vente.*
- 📋 Liste des offres de la vente (à examiner, en cours, clôturées).
- 📋 Offres et documents de la vente dans le coffre-fort, rubrique « Mandats & visites ».

## US-10.9 · Saisie par l’équipe 📋
*En tant qu’équipe Realesty, je veux saisir offres et étapes à la place des acquéreurs, agences et notaires.*
- 📋 Fonctions `staff_*` (offre, réponse de l’acquéreur, conseil, interlocuteurs, jalons, documents, compromis, acte, annulation) non appelables depuis l’app ; runbook « Suivre une vente » complété.
- 📋 Offre de démonstration (`source = demo`, `is_test`) supprimable.

## US-10.10 · Prêt pour l’app acquéreur 📋
*En tant qu’équipe produit, je veux que l’app acquéreur se branche sans migration de données.*
- 📋 `buyer_user_id`, fils de négociation, `source`, instantané contrôlé ; compteurs prévus pour vues et favoris.
- 📋 Aucune politique du vendeur ne joint les tables de l’acquéreur.
