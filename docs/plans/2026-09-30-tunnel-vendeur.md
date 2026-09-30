# Plan — Tunnel vendeur (V1 → V8)

## Contexte
L'authentification et le design system sont en place (EPIC-02, EPIC-03). Prochaine étape de la v1 : le tunnel vendeur « L’audit conversationnel » du canvas (V1 à V8b), qui constitue le dossier du bien. Travail de nuit autonome demandé par le porteur de projet, sur la branche `feat/tunnel-vendeur`, avec une Pull Request.

Cahier des charges détaillé (écrans, textes, champs, modèle de données) : [2026-09-30-tunnel-vendeur-spec.md](2026-09-30-tunnel-vendeur-spec.md).

## Décisions prises (à valider par le porteur de projet)
- **Écran d'abord** : toutes les réponses se font au clavier/à l'écran. Reportés : audit vocal (V4, micro), scan caméra/AR (V5b), extraction OCR des documents, agent « Une question ? ».
- **Données publiques gratuites** : adresse via api-adresse.data.gouv.fr (BAN), parcelle via apicarto.ign.fr (cadastre), carte `flutter_map` avec tuiles IGN.
- **Base** : nouvelles tables uniquement ajoutées (aucune modification destructive), RLS « le propriétaire du dossier seulement », appliquées par `supabase db push`.
- **Listes non spécifiées dans le design** (exposition, toiture, vitrage…) : propositions du cahier des charges, section « Open questions ».
- Coquilles du design corrigées dans l'app (« Vous serez alerté(e) », « analysés et seront ajustés »).

## Découpage (une étape = un agent codeur + un agent vérificateur, puis commit/push)
| Étape | Contenu | Dépend de |
|---|---|---|
| S1+S2 | Schéma Supabase (tables, RLS, bucket Storage privé) + package `property_repository` + `SellerTunnelCubit` + routes `/vendeur/audit/*` avec écrans provisoires + widgets partagés (en-tête du tunnel, barre d'action, cartes sélectionnables) | — |
| S3 | V1 Propriétaires | S2 |
| S4 | V3 Contexte & type de bien | S2 |
| S5+S6 | V2 Adresse (BAN) + cadastre & carte | S2 |
| S7+S8 | V4b Audit technique (mode écran) | S2 |
| S9 | V5 Méthode de relevé + V5c Surfaces (saisie manuelle) | S2 |
| S10 | V6 Cadre de vie | S2 |
| S11 | V7 Coffre de documents (upload Storage) + envoi du dossier | S1, S2 |
| S12 | V8 Attente de validation expert | S11 |
| S13–S14 | Données de marché (DVF) + V8b — optionnel | S6 |

Règles de concurrence : les agents d'une même vague ont des dossiers disjoints ; routes et écrans provisoires sont créés en S2 pour que chaque écran remplace seulement son fichier ; les chaînes l10n sont ajoutées par lecture-modification-écriture du JSON immédiatement suivie de `flutter gen-l10n`.

## Vérification
Pour chaque étape : `flutter analyze`, bloc lint, `very_good test --coverage` (100 %), tests des packages, rendu 390×844 comparé aux maquettes, build iOS release. CI GitHub verte sur la PR. Installation sur l'iPhone si connecté.

## Journal d'exécution
- 2026-09-30 soir : branche `feat/tunnel-vendeur` ; CI corrigée (docs françaises exclues du correcteur, tests des packages ajoutés) ; cahier des charges V1–V8b extrait du canvas.
- 2026-10-01 nuit — S1+S2 : migration `create_seller_tunnel` appliquée (`supabase db push`) : 7 tables, RLS « propriétaire du dossier seulement », colonnes serveur (estimation IA, statut/extraction des documents) non modifiables depuis l'app, bucket privé `property-documents` (20 Mo, PDF/JPG/PNG/HEIC) rangé par `<id utilisateur>/<id bien>/…` (et non `<id bien>/…` comme dans le cahier des charges, pour des règles Storage simples). Package `property_repository` (modèles, CRUD, Storage). `SellerTunnelCubit` porté par une `ShellRoute` sur `/vendeur/**` (pas au niveau de l'app) ; écran d'entrée « Mon dossier vendeur » ; routes `/vendeur/audit/<étape>` avec écrans provisoires, un fichier par étape. Micro masqué (`AgentActionBar.voiceEnabled = false`). `current_step` : 1–7 = V1–V7, 8 = dossier envoyé.
