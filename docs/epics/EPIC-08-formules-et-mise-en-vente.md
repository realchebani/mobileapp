# EPIC-08 · Formules & mise en vente

**Objectif** : une fois son bien (ou son lot) certifié, le vendeur choisit sa formule (L’Essentiel 1 %, Le Premium 1 %, L’Expert 3 %), signe un mandat **de test**, demande les services utiles, puis prépare et publie son annonce **dans Realesty uniquement**.
**Statut** : ✅ Livré en phase de test (saveur `development`, drapeau `SALES_ENABLED`) ; questions non bloquantes codées avec l’option recommandée (plan, « Choix par défaut en attendant le porteur de projet »).

Plan : [Formules & mise en vente](../plans/2026-10-03-offres-et-mise-en-vente.md). Spec d’origine : [Parcours vendeur V8b → V19](../plans/2026-10-01-parcours-vendeur-v8b-v19.md) (§3 V10–V11c, §6 EPIC-08). Runbook équipe : [Suivre une vente](../runbooks/suivre-une-vente.md).

Décisions applicables : **aucun paiement en v1** ; **mandat = signature de test** (case + signature dessinée, tests internes, montage juridique à valider avant tout vrai vendeur) ; notifications in-app seulement ; un lot se vend **en entier ou bien par bien** ; mise en vente dès que le **bien principal** est certifié ; l’annonce reprend **toutes les photos du dossier** (y compris avec une personne visible) ; **pas de visite 360° / vidéo immersive** avant la v3.

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-08.1 · Choisir ma formule (V10) ✅
*En tant que vendeur d’un bien certifié (ou d’un lot dont le bien principal est certifié), je veux comparer les trois formules et en choisir une.*
- ✅ Feuille à 3 onglets (Premium par défaut), contenus du design sans la promesse « visite 360° / vidéo immersive », commission estimée à partir de la valeur certifiée (somme des biens certifiés d’un lot).
- ✅ Le choix crée ma vente (`choose_formula`, rejouable) ; je peux changer de formule tant que le mandat n’est pas signé (« Besoin d’être plus accompagné ? », « Changer de formule »).
- ✅ Un bien d’un lot « ensemble » ne se vend qu’avec son lot ; un lot « ensemble ou séparément » propose « Ce bien seul » ou « Le lot » (jamais les deux en même temps) ; un lot est proposé dès que son bien principal est certifié.
- ✅ Bandeau « Phase de test : aucun paiement, mandat de test sans valeur juridique » ; accès limité à la saveur `development` (`SALES_ENABLED`).

## US-08.2 · Signer mon mandat de test ✅
*En tant que vendeur, je veux accepter et signer mon mandat dans l’app.*
- ✅ Case obligatoire + signature dessinée (`SignaturePad`) ; « Signer » toujours actif, erreurs affichées si l’une manque.
- ✅ Horodatage, version des conditions (`test-2026-10`), appareil conservés ; PDF « SPÉCIMEN » généré par `render-mandate` (empreinte SHA-256), consultable (« Voir le mandat (PDF) »).
- ✅ Pièce d’identité exigée (lien vers le coffre-fort) ; pour L’Expert, identité vérifiée par l’équipe (`staff_verify_identity`).
- ✅ Co-propriétaires indiqués « signeront hors de l’application » (`staff_record_offline_signature`).

## US-08.3 · Activer L’Essentiel (V11) ✅
- ✅ Récapitulatif de la formule et du mandat, préférences photo (« Bientôt »), assistant photo, options à la carte transformées en demandes (« Un conseiller vous recontacte »).
- ✅ « Activer et préparer mon annonce » seulement après signature (sinon message et défilement vers le mandat).

## US-08.4 · Activer Le Premium (V11b) ✅
- ✅ Demande de rappel (« Être rappelé ») à la place du prélèvement SEPA ; tarifs indicatifs.
- ✅ Shooting photo ou photo + vidéo avec jusqu’à 3 créneaux souhaités ; diagnostics présélectionnés par des règles explicites (« Présélection d’après votre audit »), modifiables.
- ✅ Étape mandat (absente de la maquette), puis préparation de l’annonce (V11a ; créneaux de visite avec EPIC-09).

## US-08.5 · Confier la vente à L’Expert (V11c) ✅
- ✅ Chronologie identité → mandat → agent ; signature désactivée tant que l’identité n’est pas vérifiée.
- ✅ Après signature : « Un agent vous contacte sous 24 h » sur la carte « Ma vente » ; l’équipe publie l’annonce (`staff_publish_expert_sale`).

## US-08.6 · Photos de mon annonce ✅
- ✅ Toutes les photos du dossier (pièces de tous les biens vendus) sont copiées dans l’annonce à la première ouverture ; « Reprendre les photos de mon dossier » recopie celles qui manquent.
- ✅ Nouvelles photos avec l’écran de prise de vue d’EPIC-15 (contrôles qualité) ou la photothèque ; couverture et retrait par photo ; 40 au plus.
- 🚧 Ordre libre par glisser-déposer : pas en v1 (seulement « Mettre en couverture »).

## US-08.7 · Préparer et publier mon annonce (V11a) ✅
- ✅ Titre et description générés depuis le dossier (modèle déterministe, aucun chiffre inventé), modifiables ou régénérés ; prix avec position dans la fourchette certifiée et commission en direct.
- ✅ « Publier » refusé avec la liste de ce qui manque (prix, titre, description, 5 photos) ; aperçu « ce que verront les acquéreurs » (commune seulement) ; diffusion « Realesty » seulement.

## US-08.8 · Suivre et retirer ma vente 🚧
- ✅ Carte « Ma vente » sur V9 (et sur la fiche du lot), statut dans « Mes biens ».
- ✅ Retrait avec confirmation intégrée (annonce retirée, mandat résilié, demandes annulées) ; mise hors ligne / republication ; prix modifiable après publication.
- 📋 « Ma formule » dans Compte (avec EPIC-11).

## US-08.9 · Être prévenu ✅
- ✅ Notifications in-app : mandat signé, identité vérifiée, demande planifiée / traitée, annonce publiée, vente retirée ; chacune ouvre la vente.

## US-08.10 · Traitement par l’équipe (avant EPIC-12) ✅
- ✅ Fonctions `staff_*` (identité, demandes, signature hors app, publication Expert) et runbook « Suivre une vente ».
