# EPIC-07 · Espace vendeur : tableau de bord & avis de valeur

**Objectif** : après l’envoi du dossier, le vendeur retrouve son bien dans un espace à onglets, suit la certification et consulte son avis de valeur certifié.
**Statut** : 🚧 En cours (socle et V8b branchés ; restent la courbe du secteur dans V9b et la mise en vente d’EPIC-08)

Plan : [Parcours vendeur V8b → V19](../plans/2026-10-01-parcours-vendeur-v8b-v19.md) (§1, §3 V9 / V9b, §4.1, §6 EPIC-07, §9 arbitrages).

Arbitrages appliqués (2026-10-01) :
- barre d’onglets **dès le début** (Mon bien · Visites · Coffre-fort · Compte) ; dossier brouillon → « Mon bien » propose Commencer / Reprendre l’audit ; déconnexion dans « Compte » ;
- rapport V9b **structuré dans l’app**, PDF facultatif ;
- notifications **dans l’app uniquement** (la promesse d’e-mail de V8 est retirée) ;
- certification : en attendant le back-office web (EPIC-12), l’équipe utilise des **fonctions SQL documentées** ([runbook](../runbooks/certifier-un-dossier.md)).

## US-07.1 · Espace vendeur à onglets ✅
*En tant que vendeur, je veux un espace avec les onglets Mon bien, Visites, Coffre-fort et Compte, pour retrouver chaque sujet en un geste.*
- ✅ Barre d’onglets conforme au design system (actif : encre + point vert), masquée sur les écrans plein écran (tunnel V1–V8).
- ✅ Chaque onglet conserve sa pile de navigation ; toucher l’onglet actif revient à sa racine.
- ✅ Dossier brouillon : « Mon bien » propose Commencer / Reprendre l’audit ; dossier envoyé : « Mon bien » = tableau de bord (V9).
- ✅ « Se déconnecter » (et le lien Design system en développement) sont dans l’onglet Compte.
- ✅ Visites et Coffre-fort affichent un écran « Bientôt » (EPIC-09, EPIC-11).
- ✅ Compte (C2, v1) : nom, e-mail, rôle, méthode de connexion, langue, déconnexion ; la modification du profil (V19) arrive avec EPIC-11.

## US-07.2 · Tableau de bord avant certification ✅
*En tant que vendeur dont le dossier est en analyse, je veux voir où en est l’expert et ma tendance IA.*
- ✅ Carte du bien (type, surface, pièces, adresse) + badge « Analyse en cours ».
- ✅ Tendance IA indicative (colonnes `ai_estimate_*`) ou message « l’expert vous donnera directement son avis de valeur ».
- ✅ Lien « Voir la synthèse du marché » → V8b (`/vendeur/marche`, EPIC-05), affiché dès que la route existe.
- ✅ Ligne « Suivi de mon dossier » → V8 ; V8 propose « Aller au tableau de bord ».
- ✅ Carte « Mon dossier » : score de transparence, documents (« Action requise » si un document est refusé), surfaces & pièces, cadre de vie, ouvrant l’aperçu des données.
- ✅ Tirer pour actualiser recharge le dossier, l’avis de valeur et les notifications.

## US-07.3 · Avis de valeur certifié sur le tableau de bord ✅
*En tant que vendeur, je veux voir ma valeur certifiée dès qu’elle est disponible.*
- ✅ Carte sombre « Avis de valeur certifié » : valeur, fourchette, tendance IA initiale, expert et date, bouton « Voir le rapport complet ».
- 🚧 « Mettre mon bien en vente » apparaît une fois certifié ; le choix de la formule (V10) arrive avec EPIC-08 (message « bientôt » en attendant).
- ✅ Notification in-app « Votre avis de valeur certifié est disponible » (cloche avec pastille, point sur l’onglet Mon bien, liste, ouverture du rapport, marquée lue).

## US-07.4 · Rapport d’avis de valeur (V9b) 🚧
*En tant que vendeur, je veux comprendre comment l’expert a fixé la valeur de mon bien.*
- ✅ 4 onglets Synthèse / Le bien / Secteur / Prix, alimentés par le rapport structuré de l’expert (`valuations`) et le dossier (pièces par niveau).
- ✅ Ventes comparables affichées avec la rue sans numéro (saisie de l’expert), ventes écartées barrées.
- ✅ « Ce qui vous revient » et « Le calcul que fera votre acquéreur » calculés dans l’app (1 % vs 4 %, frais de notaire ≈ 7,5 %).
- ✅ « Télécharger le rapport (PDF · N pages) » si un PDF existe (URL signée du bucket privé `valuation-reports`) ; mention légale avec la date de fin de validité.
- 📋 Onglet Secteur : courbe du prix au m² et chiffres du secteur depuis l’instantané de marché d’EPIC-05.
- 📋 « Mettre en vente à {valeur} » ouvre le choix de la formule (EPIC-08) ; « À proximité, à pied » et « Partager » plus tard.

## US-07.5 · Synthèse du marché dans le parcours ✅
*En tant que vendeur, je veux passer de la synthèse du marché à mon suivi ou à mon rapport.*
- ✅ V8b (EPIC-05) s’ouvre en plein écran au-dessus des onglets depuis V8 et V9 ; « Retour » et « Retour au suivi de mon dossier » reviennent à l’écran d’origine (V8 ou V9).
- 📋 « Consulter le rapport complet » en pied de V8b une fois le dossier certifié.

## US-07.6 · Certification par l’expert (back-office v1) ✅
*En tant qu’expert Realesty, je veux passer un dossier en examen puis le certifier avec mon rapport.*
- ✅ Fonctions SQL `staff_start_review`, `staff_certify_property`, `staff_attach_valuation_report` (non appelables depuis l’app), [runbook](../runbooks/certifier-un-dossier.md) en français avec un modèle JSON du rapport.
- ✅ La certification verrouille le dossier, renseigne `valuations`, passe le statut à `certified` et crée la notification in-app.
- 📋 Back-office web pour les experts : EPIC-12.

## Réalisation

- Migration `20261001162633_valuations_and_notifications.sql` : tables `valuations` (lecture seule pour le propriétaire) et `notifications` (lecture + `read_at`), bucket privé `valuation-reports`, fonctions `staff_*` ; RLS vérifiée par un bloc `DO` annulé.
- Paquet `packages/sale_repository` : `ValuationRepository` (dernier avis de valeur, URL signée du PDF) et `NotificationRepository`.
- `lib/seller_space/` : coque à onglets (`SellerTabScaffold`), Mon bien (`MyPropertyPage`), V9 (`DashboardPage`), V9b (`ReportPage` + onglets), notifications, Compte, écrans « Bientôt ».
- Design system : `RealestyTabBar`, `HeroValueCard`, `ActionCard`, `KeyValueRow`, `InitialsAvatar`, icône `download` (galerie mise à jour).
