# EPIC-08 · Formules & mise en vente

**Objectif** : une fois son bien (ou son lot) certifié, le vendeur choisit sa formule (L’Essentiel 1 %, Le Premium 1 %, L’Expert 3 %), signe un mandat **de test**, demande les services utiles, puis prépare et publie son annonce **dans Realesty uniquement**.
**Statut** : 📋 À faire (questions ouvertes ; bloquantes : Q2, Q3, Q12 du plan).

Plan : [Formules & mise en vente](../plans/2026-10-03-offres-et-mise-en-vente.md). Spec d’origine : [Parcours vendeur V8b → V19](../plans/2026-10-01-parcours-vendeur-v8b-v19.md) (§3 V10–V11c, §6 EPIC-08).

Décisions applicables : **aucun paiement en v1** ; **mandat = signature de test** (case + signature dessinée, tests internes, montage juridique à valider avant tout vrai vendeur) ; notifications in-app seulement ; lots de vente (EPIC-13) ; photos réutilisées d’EPIC-15.

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-08.1 · Choisir ma formule (V10) 📋
*En tant que vendeur d’un bien certifié (ou d’un lot entièrement certifié), je veux comparer les trois formules et en choisir une.*
- 📋 Feuille à 3 onglets, contenus du design, commission estimée à partir de la valeur certifiée (ou de la somme du lot).
- 📋 Le choix crée ma vente ; je peux changer de formule tant que le mandat n’est pas signé.
- 📋 Un bien d’un lot « ensemble » ne se vend qu’avec son lot ; un lot n’est proposé que si tous ses biens sont certifiés.
- 📋 Bandeau « phase de test » (aucun paiement, mandat de test) ; accès restreint aux testeurs.

## US-08.2 · Signer mon mandat de test 📋
*En tant que vendeur, je veux accepter et signer mon mandat dans l’app.*
- 📋 Case obligatoire + signature dessinée ; erreurs claires.
- 📋 Horodatage, version des conditions et appareil conservés ; PDF « SPÉCIMEN » consultable (et rangé dans le coffre-fort).
- 📋 Pièce d’identité exigée ; pour L’Expert, identité vérifiée par l’équipe.
- 📋 Co-propriétaires indiqués « signeront hors de l’application ».

## US-08.3 · Activer L’Essentiel (V11) 📋
- 📋 Récapitulatif de la formule et du mandat, préférences photo (« Bientôt »), options à la carte transformées en demandes (« Un conseiller vous recontacte »).
- 📋 « Activer et préparer mon annonce » seulement après signature.

## US-08.4 · Activer Le Premium (V11b) 📋
- 📋 Demande de rappel à la place du prélèvement SEPA.
- 📋 Choix du shooting et de créneaux souhaités ; diagnostics présélectionnés par des règles explicites, modifiables.
- 📋 Étape mandat, puis préparation de l’annonce (V11a).

## US-08.5 · Confier la vente à L’Expert (V11c) 📋
- 📋 Chronologie identité → mandat → agent ; signature désactivée tant que l’identité n’est pas vérifiée.
- 📋 Après signature : « Un agent vous contacte sous 24 h » sur le tableau de bord.

## US-08.6 · Photos de mon annonce 📋
- 📋 Je réutilise les photos de mes pièces (sauf « personne visible »), j’en prends de nouvelles avec l’assistant photo d’EPIC-15, je choisis l’ordre et la couverture (40 au plus).

## US-08.7 · Préparer et publier mon annonce (V11a) 📋
- 📋 Description générée sans chiffre inventé, modifiable ; prix avec position dans la fourchette certifiée et commission en direct.
- 📋 « Publier » refusé avec la liste de ce qui manque ; aperçu « ce que verront les acquéreurs » ; diffusion « Realesty » seulement.

## US-08.8 · Suivre et retirer ma vente 📋
- 📋 Carte « Ma vente » sur V9 et statut dans « Mes biens ».
- 📋 Retrait avec confirmation (annonce retirée, mandat résilié) ; mise hors ligne / republication ; prix modifiable après publication.

## US-08.9 · Être prévenu 📋
- 📋 Notifications in-app : mandat signé, identité vérifiée, demande planifiée, annonce publiée, vente retirée.

## US-08.10 · Traitement par l’équipe (avant EPIC-12) 📋
- 📋 Fonctions `staff_*` (identité, demandes, signature hors app, publication Expert) et runbook « Suivre une vente ».
