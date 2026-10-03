# EPIC-12 · Back-office expert (mini back-office web de certification) — plan d’implémentation

> Date : 2026-10-03. Statut : **proposition, questions ouvertes** (aucun code écrit).
> Sources lues : `CLAUDE.md`, `docs/decisions.md`, `docs/epics/*.md`, [spec V8b → V19](2026-10-01-parcours-vendeur-v8b-v19.md) (§4.1, §4.6, §5.1, §7 Q1–Q2, §9, §10 journal EPIC-07 : note sur les `staff_*` en `SECURITY INVOKER`), [runbook « Certifier un dossier »](../runbooks/certifier-un-dossier.md), [runbook « Suivi voix »](../runbooks/suivi-voix.md), `supabase/migrations/*` (`valuations_and_notifications`, `valuation_report_path_check`, `agent_conversations`, `voix_etendue`, `multi_biens*`, `market_estimation`, `room_photos` d’EPIC-15), `packages/sale_repository` (`Valuation`), `lib/seller_space/report/**` (V9b), plan EPIC-15 « Photos du bien », décisions EPIC-16 (traçabilité vocale).
> Plans frères (même date) : [Formules & mise en vente](2026-10-03-offres-et-mise-en-vente.md) (EPIC-08), [Coffre-fort & compte](2026-10-03-coffre-fort-et-compte.md) (EPIC-11).

---

## 0. Contexte et périmètre

Aujourd’hui, l’équipe certifie un dossier dans le **SQL Editor** de Supabase (rôle `postgres`) : `staff_start_review`, `staff_certify_property(jsonb)` avec un modèle JSON à recopier, dépôt manuel du PDF dans Storage puis `staff_attach_valuation_report`. C’est acceptable pour le porteur de projet, pas pour un **expert embauché** (accès complet à la base = aucune confidentialité) ni pour des **experts partenaires**. Les fonctions `staff_*` sont `SECURITY INVOKER` et retirées aux rôles client : le back-office doit passer par de nouvelles RPC qui contrôlent un rôle, ou par le service role côté serveur (journal EPIC-07).

**Dans le périmètre d’EPIC-12** — une application web interne, en français, pour ordinateur (≥ 1 280 px) :
1. connexion de l’équipe (lien magique) + **rôles** : administrateur, expert (embauché), expert partenaire (accès **par dossier**) ;
2. **file des dossiers** `submitted → in_review → certified`, attribution, filtres ;
3. **vue d’un dossier** : données du bien avec provenance, propriétaires, lot, **photos** par pièce (EPIC-15), **documents** (ouvrir, vérifier, refuser avec motif), **traçabilité vocale** (fil de conversation `agent_turns` ; fiche de remplissage d’EPIC-16 dès qu’elle existe), instantané de marché (EPIC-05) ;
4. **formulaire structuré de l’avis de valeur** (brouillon enregistré, contrôles identiques à la base, pré-remplissage depuis le dossier et l’instantané DVF), **certification**, **dépôt du PDF** ;
5. **lots** (contexte du lot, certification bien par bien), vérification d’identité (EPIC-08), **journal d’audit** ;
6. sécurité : **aucun service role dans le navigateur**, lectures et écritures par RPC / Edge Functions avec contrôle de rôle, MFA, CSP.

**Hors périmètre** : application mobile de l’expert (constat de visite sur place), facturation des experts partenaires, saisie des offres / visites / contacts de vente (EPIC-09 / EPIC-10 l’ajouteront au même back-office), messagerie avec le vendeur, statistiques.

## 1. Décisions déjà prises

| Décision | Source | Conséquence ici |
|---|---|---|
| **Mini back-office web** pour les experts ; **expert embauché** (rôle dédié, accès restreint, confidentialité) et **experts partenaires** (saisie directe ou rapports saisis par l’équipe) | `decisions.md` 2026-10-01, spec §9 Q1 | Rôles `admin`, `expert`, `partner_expert` ; un partenaire ne voit que les dossiers qui lui sont attribués ; l’équipe peut saisir un rapport « pour » un partenaire (champ « Expert signataire »). |
| **Rapport V9b structuré + PDF facultatif** | `decisions.md` 2026-10-01 | Le formulaire produit exactement le JSON de `valuations` ; le PDF reste facultatif. |
| **Certification par bien** (lots : valeur de lot éventuelle plus tard) | EPIC-13 Q8 | Chaque bien d’un lot est certifié séparément ; la vue montre le lot. |
| **Notifications in-app seulement** | `decisions.md` 2026-10-01 | Les actions du back-office écrivent des `notifications` (mêmes textes que les `staff_*`). |
| **Traçabilité vocale pour l’expert** : fil de conversation + fiche de remplissage (champ, valeur, phrase d’origine) ; pré-remplissage inter-étapes « À confirmer », phrase d’origine conservée | `decisions.md` 2026-10-02 (EPIC-16) | Onglet « Voix » : fil maintenant (`agent_sessions` / `agent_turns`), fiche quand le schéma d’EPIC-16 existe. |
| **Photos pour l’expert et l’annonce**, analyse IA consentie, défauts montrés | `decisions.md` 2026-10-02 (EPIC-15) | Onglet « Photos » : par pièce, contrôles qualité, analyse IA « à vérifier ». |
| Clés secrètes jamais dans une app ; seule la clé publishable côté client | `CLAUDE.md` | Le navigateur n’a que la clé publishable ; service role uniquement dans les Edge Functions. |
| Une branche / PR par epic | `decisions.md` 2026-10-01 | `feat/epic-12-back-office` (+ éventuellement une PR préparatoire pour l’extraction du design system, Q2). |

## 2. Choix technique et hébergement

### 2.1 Options

| | (A) **Flutter web dans le même dépôt** (`backoffice/`) | (B) Petite app web séparée (Vite + React / Refine, ou SvelteKit) dans `backoffice-web/` | (C) Outil d’admin hébergé (Retool, Appsmith) ou Supabase Studio + runbooks |
|---|---|---|---|
| Réutilisation | design system, modèles (`Valuation`, `Property`), dépôts, règles de format (`frenchNumber`), **widgets de V9b pour l’aperçu vendeur** | aucune (types à régénérer : `supabase gen types`) | aucune |
| Compétences / outillage | Dart seul, mêmes lints, tests, CI, couverture 100 % | deuxième pile (npm, licences, CI) | peu de code, mais logique dans l’outil |
| Ergonomie web (tableaux, sélection de texte, fichiers) | correcte avec `SelectionArea`, `DataTable` ; poids initial ~2–3 Mo (CanvasKit) | excellente | bonne pour du CRUD |
| Sécurité | identique (RLS / RPC) ; CSP à soigner (CanvasKit auto-hébergé) | identique | données chez un tiers (C) ou accès base complet (Studio) : **incompatible** avec experts partenaires |
| Coût | 0 € | 0 € | payant au-delà de quelques utilisateurs |

**Recommandation : (A) Flutter web**, application distincte `backoffice/` (son propre `pubspec.yaml`, package `realesty_backoffice`) dans le dépôt, dépendant par chemin des paquets `packages/*` (web-compatibles, sauf `voice_repository` non utilisé) et d’un paquet de design system partagé (Q2). L’argument décisif : l’expert voit **l’aperçu exact de ce que verra le vendeur** (onglets V9b) avant de certifier, sans réécrire l’affichage.

### 2.2 Hébergement (Q3)
**Recommandé : Cloudflare Pages** (gratuit, domaine personnalisé `expert.realesty.fr`, fichier `_headers` pour CSP / HSTS / `X-Frame-Options`, aperçus par branche), déployé par GitHub Actions (`wrangler pages deploy build/web`, secret `CLOUDFLARE_API_TOKEN`) au merge sur `main`. En option, **Cloudflare Access** (gratuit jusqu’à 50 utilisateurs) devant le site : une seconde barrière (OTP e-mail) avant même de charger l’app. Seuls des fichiers statiques y sont servis ; les données restent dans Supabase (UE). Alternatives : Netlify, Vercel, Firebase Hosting (équivalents) ; GitHub Pages (pas d’en-têtes HTTP personnalisés : déconseillé).

Construction : `flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/backoffice.json` (CanvasKit servi par le site, pas par gstatic, pour une CSP stricte `script-src 'self' 'wasm-unsafe-eval'`).

## 3. Authentification et rôles

### 3.1 Connexion
- **Lien magique** Supabase (PKCE web), redirection `https://expert.realesty.fr/auth/callback` ajoutée aux URL autorisées (`supabase/config.toml` + `supabase config push`). Les limites d’envoi d’e-mails du fournisseur par défaut s’appliquent (équipe de l’organisation) : le SMTP Brevo du backlog devient nécessaire avant d’inviter un **partenaire** externe.
- **MFA TOTP obligatoire** pour tout membre de l’équipe (Q5) : Supabase Auth MFA (gratuit) ; enrôlement au premier accès ; toutes les fonctions `bo_*` exigent `auth.jwt() ->> 'aal' = 'aal2'`.
- Un compte d’équipe est un utilisateur Supabase ordinaire (le trigger `handle_new_user` lui crée un profil sans rôle) ; son accès vient **uniquement** de `staff_members`.

### 3.2 Rôles : table plutôt que « custom claims » (Q4)
`staff_members` (une ligne = un accès) :

| Colonne | Règle |
|---|---|
| `user_id` | uuid pk → `auth.users` on delete cascade |
| `role` | check in (`admin`, `expert`, `partner_expert`) |
| `display_name`, `initials` | affichés au vendeur (« Julien M. », « JM ») |
| `organisation` | text ≤ 120 (cabinet du partenaire) |
| `active` | bool not null default true |
| `created_at`, `created_by`, `deactivated_at` | |

Fonctions d’aide (`security definer`, `stable`, `set search_path = ''`, exécution `authenticated`) :
- `bo_role() returns text` : rôle actif de `auth.uid()` si `aal2`, sinon null ;
- `bo_can_access_property(p_property_id uuid) returns boolean` : `admin` / `expert` → tout bien `status <> 'draft'` ; `partner_expert` → bien attribué (attribution non révoquée) ; sinon false.

Pourquoi pas des *custom claims* (Auth Hook) : la révocation n’agirait qu’à l’expiration du jeton (≤ 1 h) et la logique serait dupliquée ; la table est lue à chaque appel (index pk), la révocation est **immédiate**. Les claims restent possibles plus tard pour l’affichage.

Premier administrateur : inséré au SQL Editor (runbook) ; ensuite écran « Équipe » (admin seulement).

### 3.3 Ce que voit chaque rôle (Q6)

| Donnée | admin | expert | partner_expert |
|---|---|---|---|
| File : tous les dossiers envoyés | ✔ | ✔ | dossiers attribués seulement |
| Données du bien, pièces, cadre de vie, photos, voix, instantané de marché | ✔ | ✔ | ✔ (attribués) |
| Propriétaires : nom complet, téléphone, e-mail | ✔ | ✔ | **initiales + commune** |
| Pièces d’identité | ✔ | ✔ | ✘ |
| Autres documents | ✔ | ✔ | ✔ |
| Certifier | ✔ | ✔ | **soumet pour validation** (Q7) |
| Attribuer, gérer l’équipe, lire tout le journal | ✔ | ✘ | ✘ |
| Vérifier une identité (EPIC-08) | ✔ | ✔ | ✘ |

## 4. Modèle de données — migration `AAAAMMJJhhmmss_back_office.sql`

### 4.1 Tables
- **`staff_members`** (§3.2). RLS : `select` de sa propre ligne ; `admin` lit tout. Aucune écriture directe (RPC admin).
- **`dossier_assignments`** : `id`, `property_id` → `properties` on delete cascade, `expert_user_id` → `staff_members`, `assigned_by`, `assigned_at`, `revoked_at`, `note` ≤ 300 ; `unique (property_id) where revoked_at is null` (un responsable à la fois). Lecture : admin, et l’expert concerné.
- **`valuation_drafts`** : `property_id` pk → `properties` on delete cascade, `payload jsonb` (mêmes clés que `staff_certify_property`), `version int not null default 1` (verrou optimiste), `updated_by`, `updated_at`, `status` check in (`editing`, `submitted_for_approval`), `submitted_by`, `submitted_at`, `approval_note`. Lecture / écriture **par RPC uniquement**.
- **`staff_audit_log`** (ajout seul) : `id bigint identity`, `at timestamptz default now()`, `actor_user_id`, `actor_role`, `action` text (`dossier_opened`, `file_signed`, `review_started`, `draft_saved`, `submitted_for_approval`, `certified`, `report_attached`, `document_verified`, `document_rejected`, `identity_verified`, `assigned`, `unassigned`, `member_added`, `member_deactivated`, `sql_editor`), `property_id` null, `target_type`, `target_id`, `details jsonb`. RLS : `select` admin ; **aucun** grant d’insert / update / delete à `authenticated` ; écrit seulement par les fonctions `security definer`. Un trigger refuse `update` / `delete` même au propriétaire de la table (sauf rôle `postgres` explicite pour la purge, Q10).

### 4.2 Pas de nouvelles politiques de lecture sur les tables du vendeur
Plutôt que d’ajouter des politiques « équipe » sur `properties`, `property_owners`, `rooms`, `room_photos`, `agent_turns`… (risque d’élargir par erreur l’accès vendeur, et impossible de masquer des colonnes par rôle), **toutes les lectures passent par des RPC `security definer`** qui contrôlent `bo_can_access_property`, façonnent la réponse selon le rôle (§3.3) et écrivent le journal. Les tables du vendeur gardent exactement leurs politiques actuelles.

### 4.3 RPC du back-office (`bo_*`, `security definer`, `set search_path = ''`, `authenticated`, toutes vérifient `bo_role()` et `aal2`)

| Fonction | Rôles | Effet |
|---|---|---|
| `bo_me()` | équipe | rôle, nom, MFA requis ou non |
| `bo_list_dossiers(p_status text[], p_assigned text, p_search text, p_limit int, p_cursor text)` | tous (filtré) | file : bien (type, commune, surface), vendeur (initiales), lot, statut, envoyé le, attribué à, ancienneté, documents à vérifier, documents ajoutés après l’envoi, photos, voix (oui / non), brouillon de rapport |
| `bo_get_dossier(p_property_id)` | accès au bien | JSON complet : bien + provenance, propriétaires (masqués pour partenaire), parcelles, estimations antérieures, pièces (+ description, source), cadre de vie, documents (sans URL), photos (sans URL) + qualité + analyse, sessions / tours vocaux, fiche de remplissage (EPIC-16 si présente), instantané de marché, lot et ses biens (statuts), avis de valeur existant, brouillon ; journalise `dossier_opened` |
| `bo_assign(p_property_id, p_expert_user_id)` / `bo_unassign` | admin | attribution ; notification interne (aucune au vendeur) |
| `bo_start_review(p_property_id)` | admin, expert, partenaire attribué | = `staff_start_review` (statut `in_review`, verrou, notification vendeur) |
| `bo_save_draft(p_property_id, p_payload jsonb, p_expected_version int) returns int` | idem | enregistre, `version + 1` ; conflit → erreur `draft_conflict` (deux experts) |
| `bo_validate_draft(p_property_id) returns jsonb` | idem | liste des erreurs (mêmes contrôles que la table `valuations` + règles du runbook : rue sans numéro, montants entiers, provenance connue) — sans écrire |
| `bo_submit_for_approval(p_property_id, p_expected_version)` | partenaire | brouillon `submitted_for_approval` |
| `bo_certify(p_property_id, p_expected_version) returns uuid` | admin, expert | valide puis appelle la logique commune `_certify_property(property, payload, actor)` : insère `valuations` (avec `expert_user_id` = l’expert signataire), statut `certified`, notification vendeur ; supprime le brouillon |
| `bo_attach_report(p_property_id, p_storage_path, p_pages)` | admin, expert | = `staff_attach_valuation_report` (chemin et objet vérifiés) |
| `bo_verify_document(p_document_id)` / `bo_reject_document(p_document_id, p_reason)` | admin, expert (partenaire : selon Q6) | colonnes d’EPIC-11 (`verified_at`, `rejected_reason`) + notification vendeur |
| `bo_verify_identity(p_property_owner_id)` | admin, expert | colonne d’EPIC-08 (`identity_verified_at`) + notification |
| `bo_list_team()`, `bo_upsert_member(...)`, `bo_deactivate_member(...)` | admin | équipe ; un admin ne peut pas se désactiver lui-même |
| `bo_audit(p_property_id, p_limit, p_cursor)` | admin (et l’expert pour ses propres actions) | journal |

**Refactorisation des `staff_*`** : la logique de `staff_start_review`, `staff_certify_property` et `staff_attach_valuation_report` passe dans des fonctions internes `_start_review`, `_certify_property`, `_attach_report` (`security definer`, exécution retirée à tous les rôles client) ; les `staff_*` existantes deviennent des enveloppes qui journalisent `actor_role = 'sql_editor'`. Le runbook reste valable (repli en cas de panne du back-office). Les fonctions `staff_*` ajoutées par EPIC-08 / EPIC-11 suivent le même schéma.

Les RPC qui dépendent d’un autre epic (`bo_verify_document` → EPIC-11, `bo_verify_identity` → EPIC-08, fiche vocale → EPIC-16, photos → EPIC-15) sont créées **dans une migration de l’epic qui arrive en second** ; le back-office masque l’action tant que la RPC n’existe pas (`bo_me()` renvoie la liste des capacités disponibles).

### 4.4 Fichiers : Edge Function `bo-files` (aucune politique Storage pour l’équipe)
- `POST {action: "sign_download", property_id, paths[]}` : vérifie avec le **JWT de l’appelant** (`rpc('bo_check_files', …)`, qui contrôle le rôle, l’accès au bien, que chaque chemin appartient bien à ce dossier — `property_documents.storage_path`, `room_photos.storage_path`, `valuations.report_storage_path` — et qu’un partenaire ne demande pas une pièce d’identité) puis signe avec le service role (**5 minutes**), journalise `file_signed` (une ligne par lot de chemins). Miniatures : l’app web demande les photos d’une pièce en un appel.
- `POST {action: "sign_upload", property_id, file_name, pages}` : rôle admin / expert, chemin calculé côté serveur `<owner id>/<property id>/avis-de-valeur-<date>.pdf` dans `valuation-reports`, URL d’envoi signée (`createSignedUploadUrl`) ; l’app envoie le PDF puis appelle `bo_attach_report`.
- Conséquence côté vendeur : la mention « chaque consultation par l’équipe est enregistrée » devient vraie (plan EPIC-11, Q5).

### 4.5 Notifications
Contrôle `notifications.kind` remplacé de façon idempotente par le format `^[a-z][a-z_]{2,39}$` (même instruction que les plans frères). Aucun nouveau type propre au back-office : il réutilise `review_started`, `valuation_certified`, `document_rejected`, `document_verified`, `identity_verified`.

### 4.6 Sonde RLS / RPC (bloc `DO` annulé, en simulant `request.jwt.claims` avec `aal`)
Vendeur : `bo_*` refusées ; `staff_members`, `valuation_drafts`, `staff_audit_log` invisibles. Expert sans `aal2` : refus. Partenaire : dossier non attribué refusé, propriétaires masqués, pièce d’identité refusée par `bo_check_files`, `bo_certify` refusée, `bo_submit_for_approval` acceptée. Expert : certifie, brouillon en conflit refusé. Admin : attribue, désactive un membre → accès coupé immédiatement. Journal : aucune modification possible. Tables du vendeur : politiques inchangées (lecture d’un dossier par un expert **directement** sur `properties` → aucune ligne).

## 5. Écrans du back-office (aucune maquette : design system Realesty, mise en page bureau)

Structure : barre latérale (File, Mes dossiers, Équipe [admin], Journal [admin], compte / déconnexion), contenu en largeur fluide (≥ 1 280 px ; message « Écran trop étroit » en dessous de 1 024 px). Routage `go_router` (`/connexion`, `/mfa`, `/dossiers`, `/dossiers/<id>/<onglet>`, `/equipe`, `/journal`).

1. **Connexion** : e-mail → lien magique ; écran « Accès refusé » si l’utilisateur n’est pas membre actif ; **MFA** (enrôlement QR TOTP, puis code à chaque session).
2. **File des dossiers** : tableau triable (envoyé le, ancienneté avec alerte > 48 h, bien « Maison · 115 m² · Chaponost », lot, statut `Envoyé` / `En examen` / `Certifié`, attribué à, indicateurs : documents à vérifier, « + 2 après l’envoi », photos, voix, brouillon) ; filtres : statut, « Mes dossiers », « Non attribués », recherche (commune, id) ; actions de ligne : attribuer (admin), « Prendre en charge » (`bo_start_review`). Les biens d’un même lot sont regroupés visuellement.
3. **Dossier** — en-tête : bien, statut, lot (« Lot : Maison + terrain · 1/2 certifié » avec liens vers les autres biens), propriétaire(s), attribution, boutons « Prendre en charge » / « Certifier ».
   - **Synthèse** : toutes les réponses du tunnel par étape (V1–V7) avec **provenance** (`Déclaré`, `Document`, `Externe`, `Dicté`, `À confirmer` d’EPIC-16), parcelles (liste + lien Géoportail), estimations antérieures, tendance IA et instantané DVF (fourchette, confiance, rayon / période, comparables).
   - **Photos** (EPIC-15) : grille par pièce (pièces principales sans photo signalées), visionneuse plein écran, contrôles qualité, analyse IA « suggestion à vérifier » (type de pièce, revêtement, vitrage, constats, personne visible).
   - **Documents** : liste par rubrique (types d’EPIC-11), statut, « ajouté après l’envoi », ouvrir (URL signée, nouvel onglet), « Vérifier » / « Refuser » (motif obligatoire, modèles de motifs : illisible, incomplet, mauvais document, expiré) ; pièces d’identité : « Identité vérifiée » par propriétaire (EPIC-08).
   - **Voix** : sessions par étape, fil chronologique (transcription du vendeur, réponse de l’agent, valeurs extraites / rejetées et raisons, tours annulés barrés) ; **fiche de remplissage** (EPIC-16) : champ · valeur · phrase d’origine · confirmé ou non ; rappel : transcriptions de V1 et adresses dictées non conservées.
   - **Avis de valeur** : formulaire §6, enregistrement automatique, erreurs en direct, « Aperçu vendeur » (onglets V9b), « Certifier » / « Soumettre pour validation », dépôt du PDF (après certification aussi).
   - **Journal** : actions sur ce dossier (admin ; l’expert voit les siennes).
4. **Équipe** (admin) : membres, rôle, organisation, actif ; ajouter (e-mail d’un utilisateur existant → `bo_upsert_member`), désactiver ; attributions en cours.
5. **Journal** (admin) : filtrable par personne, action, dossier, période ; export CSV (fichier téléchargé côté navigateur).

## 6. Formulaire de l’avis de valeur (remplace le modèle JSON du runbook)

Sections calquées sur les onglets V9b et les clés de `staff_certify_property` :

| Section | Champs | Aides |
|---|---|---|
| Valeur | `value_eur`, `low_eur`, `high_eur` (contrôle `low ≤ value ≤ high`, 1 000 – 100 M€), `price_m2_eur` (calculé, modifiable), `estimated_delay_weeks`, `valid_until` (certification + 3 mois) | tendance IA et fourchette DVF affichées à côté |
| Expert | expert signataire (`expert_display_name`, `expert_initials`, `expert_user_id`) — par défaut l’utilisateur ; l’admin peut choisir un partenaire (« rapport saisi par l’équipe ») | |
| Synthèse | `method_steps[]` (libellé, détail, montant, `is_delta`), `reasons[]` (positif / négatif, texte), `delay_curve[]`, `expert_quote` (≤ 2 000) | listes éditables (ajout, ordre, suppression) |
| Le bien | `description` (≤ 4 000), `technical_sheet[]` (libellé, valeur, provenance `declared` / `document` / `external` / `verified`) | **pré-remplie** depuis le dossier (année, matériaux, toiture, chauffage, assainissement, DPE…) avec la provenance du dossier ; l’expert promeut en « Vérifié » |
| Secteur | `comparables[]` (rue **sans numéro**, date, surface, terrain, prix, écartée), `comparables_note`, `competitors_summary`, `competitors[]`, `risks_note` | **import des comparables de l’instantané DVF** (cases « retenue / écartée ») ; numéro de rue refusé par validation (`^\d` interdit) |
| Prix | `adjustments[]` (base / ligne / total), `method_summary[]` (ligne / total / contrôle), `works_label`, `works_estimate_eur`, `sources` | totaux recalculés et comparés (avertissement si la somme ne tombe pas sur la valeur) |
| PDF | fichier + nombre de pages | après certification aussi |

- Enregistrement automatique (5 s après la dernière frappe et en quittant un champ) via `bo_save_draft` ; indicateur « Enregistré · v12 » ; conflit → bandeau « Modifié par X : recharger ».
- Les contrôles côté client sont des fonctions Dart **pures et partagées** avec `bo_validate_draft` (mêmes messages ; test de parité sur une fixture JSON, comme les profils de type d’EPIC-13).
- « Certifier » : récapitulatif (valeur, fourchette, sections vides masquées chez le vendeur) + confirmation intégrée ; irréversible depuis le back-office (correction : runbook « Corriger une erreur », ou `bo_amend` plus tard — Q9).

## 7. Données et code

- `backoffice/` (Flutter web) : `lib/app/` (routeur, session, garde MFA), `lib/queue/`, `lib/dossier/` (onglets), `lib/valuation_form/` (formulaire, validations pures), `lib/team/`, `lib/audit/`, `lib/l10n/` (français seul) ; tests miroirs, couverture 100 %, `very_good_analysis`, `bloc_lint`.
- **`packages/backoffice_repository`** (nouveau, Dart pur + `supabase`) : `BackOfficeRepository` (RPC `bo_*`, `bo-files`), modèles (`DossierSummary`, `Dossier`, `ValuationDraft`, `StaffMember`, `AuditEntry`), et **`ValuationDraftValidator`** partagé (pur). Réutilise `Valuation` de `sale_repository` pour l’aperçu.
- **Design system partagé** (Q2) : extraction de `lib/ui/` en `packages/realesty_ui` (tokens, typographies avec `package: 'realesty_ui'`, polices déplacées, composants, icônes, `frenchNumber`), `lib/ui/ui.dart` réexporte le paquet pour ne toucher aucun import de l’app. L’aperçu V9b demande aussi d’extraire les blocs de `lib/seller_space/report/` vers un paquet `realesty_report` (ou d’y rendre le rapport à partir du seul `Valuation`) — tranche B9, facultative.
- CI : job `flutter_web` (analyse, format, tests, `flutter build web`) pour `backoffice/` ; job `dart_package` pour `backoffice_repository` (et `realesty_ui`) ; déploiement Cloudflare sur `main` ; tests Deno pour `bo-files`.
- Config : `backoffice/config/{development,production}.json` (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `AUTH_REDIRECT_URL`) — clé publishable seulement.

## 8. User stories (EPIC-12)

- **US-12.1 · Se connecter de façon sûre** — *En tant que membre de l’équipe, je me connecte par lien magique puis code TOTP ; sans rôle actif, je vois « Accès refusé ».* Critères : MFA obligatoire ; désactivation effective immédiatement ; session expirée → reconnexion ; aucune clé secrète dans les fichiers servis (contrôle CI : recherche de `service_role` / `sb_secret_` dans `build/web`).
- **US-12.2 · Gérer l’équipe (admin)** — ajouter un expert ou un partenaire (organisation), le désactiver ; attribuer un dossier ; un partenaire ne voit que ses dossiers.
- **US-12.3 · Voir la file** — dossiers envoyés triés par ancienneté, filtres, indicateurs (documents à vérifier, ajouts après l’envoi, photos, voix, brouillon), lots regroupés ; « Prendre en charge » passe le dossier en examen et prévient le vendeur.
- **US-12.4 · Examiner un dossier** — réponses avec provenance, propriétaires (masqués pour un partenaire), lot, photos par pièce avec contrôles et analyse IA, documents ouverts en un clic, instantané DVF ; chaque ouverture de dossier et de fichier est journalisée.
- **US-12.5 · Vérifier les documents et l’identité** — vérifier / refuser avec motif ; le vendeur reçoit « Un document est à remplacer » et voit le motif dans son coffre-fort ; identité vérifiée par propriétaire (débloque la signature Expert d’EPIC-08).
- **US-12.6 · Suivre ce qui a été dit** — fil vocal par étape (transcriptions, valeurs extraites ou rejetées, tours annulés) et fiche de remplissage (champ, valeur, phrase d’origine, confirmé) quand EPIC-16 la fournit.
- **US-12.7 · Rédiger l’avis de valeur** — formulaire structuré pré-rempli (fiche technique, comparables DVF), enregistrement automatique avec gestion des conflits, erreurs identiques à la base, aperçu vendeur.
- **US-12.8 · Certifier et joindre le PDF** — un expert certifie (statut `certified`, notification, rapport visible sur V9 / V9b) ; un partenaire soumet pour validation, un expert ou l’admin certifie ; PDF envoyé par URL signée et lié.
- **US-12.9 · Lots** — la vue indique le lot, le mode de vente, l’état de chaque bien et permet de passer de l’un à l’autre ; chaque bien est certifié séparément.
- **US-12.10 · Journal d’audit** — toute action (ouvertures comprises) est journalisée, non modifiable ; l’admin filtre et exporte.

## 9. Découpage

| # | Tranche | Fichiers possédés | Dépend de |
|---|---|---|---|
| B0 | Extraction `packages/realesty_ui` (+ réexport `lib/ui/ui.dart`, polices, galerie, tests ; CI) | `packages/realesty_ui/**`, `lib/ui/**`, `pubspec.yaml`, `assets/fonts/**`, `.github/workflows/main.yaml` | Q2 ; **fenêtre sans autre branche touchant `lib/ui`** |
| B1 | Migration `*_back_office.sql` : `staff_members`, `dossier_assignments`, `valuation_drafts`, `staff_audit_log`, `bo_role`, `bo_can_access_property`, refactorisation `staff_*` → internes, `bo_*` de base (me, list, get, assign, start_review, drafts, validate, submit, certify, attach, team, audit, check_files) ; sonde ; runbook mis à jour (premier admin, repli SQL) | `supabase/migrations/*_back_office.sql`, `docs/runbooks/certifier-un-dossier.md`, nouveau `docs/runbooks/back-office.md` | Q4, Q6, Q7 |
| B2 | Edge Function `bo-files` + tests Deno + déploiement | `supabase/functions/bo-files/**`, `supabase/functions/tests/bo_files_test.ts` | B1 |
| B3 | `packages/backoffice_repository` + `ValuationDraftValidator` + fixture de parité avec `bo_validate_draft` ; CI | `packages/backoffice_repository/**`, `supabase/functions/tests/fixtures/valuation_drafts.json` (ou `supabase/tests/`) | B1 |
| B4 | Squelette `backoffice/` : app, routeur, connexion lien magique, MFA, garde de rôle, coque, config, CI web, `_headers`, déploiement Cloudflare | `backoffice/{pubspec.yaml,lib/app/**,web/**,config/**}`, `.github/workflows/backoffice.yaml`, `supabase/config.toml` (URL de redirection) | B0 (ou thème local temporaire), B3, Q3, Q5 |
| B5 | File des dossiers + attribution | `backoffice/lib/queue/**` | B4 |
| B6 | Vue dossier : en-tête, lot, Synthèse, Documents (ouverture, vérifier / refuser si EPIC-11 présent), Photos (si EPIC-15 présent) | `backoffice/lib/dossier/{header,synthesis,documents,photos}/**` | B2, B5 |
| B7 | Onglet Voix (fil) ; fiche de remplissage quand EPIC-16 la livre (tranche B7b) | `backoffice/lib/dossier/voice/**` | B6 ; EPIC-16 pour B7b |
| B8 | Formulaire de l’avis de valeur, enregistrement automatique, validation, certification, soumission partenaire, dépôt PDF | `backoffice/lib/valuation_form/**` | B3, B6 |
| B9 | Aperçu vendeur (rendu V9b) — facultatif | `packages/realesty_report/**` (extrait de `lib/seller_space/report/**`) ou `backoffice/lib/valuation_form/preview/**` | B0, B8, Q8 |
| B10 | Équipe + Journal (admin), export CSV | `backoffice/lib/{team,audit}/**` | B4 |
| B11 | Identité (EPIC-08) et motifs de refus ; intégration, `CLAUDE.md`, epic, journal ; essai bout en bout sur un dossier de test (certification visible sur l’iPhone) | `backoffice/lib/dossier/identity/**`, docs | B6, EPIC-08 / EPIC-11 |

Vagues : **{B0, B1}** → **{B2, B3}** → **{B4}** → **{B5, B10}** → **{B6}** → **{B7, B8}** → **{B9, B11}**.

Ordre entre epics conseillé : **EPIC-11 avant ou en parallèle** (colonnes de vérification des documents), **EPIC-12 avant l’arrivée d’un expert embauché ou partenaire** ; EPIC-08 n’en dépend pas (repli `staff_verify_identity`). B0 doit être planifiée hors des fenêtres où EPIC-08 (O0) ajoute des composants à `lib/ui` : soit B0 d’abord puis EPIC-08 ajoute dans le paquet, soit l’inverse.

## 10. Sécurité (récapitulatif)

1. **Navigateur** : clé publishable seule ; contrôle CI qui échoue si `build/web` contient `service_role` ou `sb_secret_`.
2. **Base** : tables du vendeur inchangées ; l’équipe lit et écrit **uniquement** par des RPC `security definer` (`set search_path = ''`) qui vérifient `bo_role()`, `aal2`, l’accès au bien et l’état courant, et journalisent.
3. **Fichiers** : aucune politique Storage pour l’équipe ; URL signées de 5 min émises par `bo-files` après contrôle avec le JWT de l’appelant ; pièces d’identité interdites aux partenaires.
4. **Comptes** : MFA TOTP, désactivation immédiate (table), pas de compte partagé, un admin ne peut pas se retirer lui-même ; un membre de l’équipe ne peut pas supprimer son compte depuis l’app vendeur (EPIC-11).
5. **Web** : CSP stricte (`default-src 'self'`, `connect-src` = projet Supabase, `frame-ancestors 'none'`), HSTS, CanvasKit auto-hébergé, aucune ressource tierce ; Cloudflare Access en option.
6. **Confidentialité** : accord de confidentialité / sous-traitance RGPD signé par chaque expert partenaire avant accès (processus, Q6) ; minimisation (partenaire : initiales + commune).
7. **Journal** : append-only, conservation définie (Q10), export par l’admin.

## 11. Risques

| Risque | Parade |
|---|---|
| Extraction du design system (B0) en conflit avec les branches en cours | Réexport `lib/ui/ui.dart` (aucun import à changer), fenêtre dédiée, PR préparatoire courte ; repli : thème local minimal du back-office construit sur les mêmes jetons copiés. |
| Flutter web : poids, rendu des tableaux, sélection de texte | Usage bureau interne ; `SelectionArea`, `PaginatedDataTable` ; mesure du temps de chargement. |
| Envoi des liens magiques aux partenaires (limites du fournisseur e-mail par défaut) | SMTP Brevo (backlog) avant le premier partenaire ; d’ici là, comptes équipe seulement. |
| Un seul projet Supabase pour dev / test / prod | Le back-office pointe vers le même projet ; le projet de production séparé (backlog) devient prioritaire avant de vrais vendeurs. |
| Dépendances d’epics (EPIC-08 identité, EPIC-11 documents, EPIC-15 photos, EPIC-16 fiche vocale) | Capacités annoncées par `bo_me()` ; onglets et actions masqués tant que l’objet n’existe pas ; RPC correspondantes livrées par l’epic qui arrive en second. |
| Erreur de certification irréversible | Récapitulatif + confirmation ; runbook de correction ; `bo_amend` plus tard (Q9). |
| Divergence entre validations client et base | Validateur Dart partagé + fixture de parité avec `bo_validate_draft`. |

## 12. Questions ouvertes

Légende : **🔴 bloquante** · **🟢 défaut réversible**.

1. **Technologie** 🔴 (avant B4) — (a) **Flutter web dans le dépôt (`backoffice/`), design system et modèles partagés** (recommandé) ; (b) petite app web séparée (React + Refine ou SvelteKit) dans le dépôt ; (c) outil d’admin hébergé (Retool / Appsmith) — exclu pour des partenaires externes à cause de la confidentialité.
2. **Partage du design system** 🟢 (avant B0 / B4) — (a) **extraire `lib/ui` en `packages/realesty_ui` (réexport pour l’app)** (recommandé) ; (b) le back-office a son propre petit thème avec les mêmes jetons (copie) ; (c) le back-office dépend du paquet `mobileapp` entier par chemin (rapide, mais tire toutes les dépendances mobiles et casse les polices).
3. **Hébergement et domaine** 🟢 (avant B4) — (a) **Cloudflare Pages sur `expert.realesty.fr`, déploiement par GitHub Actions, Cloudflare Access en option** (recommandé) ; (b) Netlify / Vercel ; (c) Firebase Hosting. Confirmer le **sous-domaine** et l’accès DNS de `realesty.fr`.
4. **Rôles : table ou custom claims** 🔴 (avant B1) — (a) **table `staff_members` lue par des fonctions `security definer` (révocation immédiate)** (recommandé) ; (b) custom claims via Auth Hook (`app_metadata.role`, révocation à l’expiration du jeton) ; (c) les deux (claims pour l’affichage, table pour l’autorité).
5. **MFA** 🟢 (avant B4) — (a) **TOTP obligatoire pour toute l’équipe (`aal2` exigé par les RPC)** (recommandé) ; (b) obligatoire pour les partenaires seulement ; (c) pas de MFA en phase de test (lien magique seul).
6. **Périmètre d’un expert partenaire** 🔴 (avant B1) — (a) **dossiers attribués seulement ; propriétaires réduits à initiales + commune ; pas de pièces d’identité ; peut vérifier / refuser les autres documents** (recommandé) ; (b) accès complet aux dossiers attribués (noms, coordonnées, identité) ; (c) aucune connexion : l’équipe saisit leurs rapports (seuls admin / expert embauché utilisent le back-office).
7. **Certification par un partenaire** 🔴 (avant B1) — (a) **le partenaire soumet, un expert embauché ou l’admin valide et certifie (double regard pendant les tests)** (recommandé) ; (b) le partenaire certifie directement ; (c) seul l’admin certifie, quel que soit l’auteur.
8. **Aperçu vendeur dans le back-office** 🟢 — (a) **oui, en réutilisant les widgets de V9b (extraction en paquet, tranche B9)** (recommandé, après le reste) ; (b) aperçu simplifié propre au back-office ; (c) pas d’aperçu (vérification sur l’iPhone de test).
9. **Corriger un avis de valeur certifié** 🟢 — (a) **v1 : runbook SQL (repli) ; plus tard `bo_amend` qui crée une nouvelle ligne `valuations` (l’app lit la plus récente) et notifie** (recommandé) ; (b) `bo_amend` dès v1 ; (c) jamais de correction : une nouvelle certification complète.
10. **Conservation du journal d’audit** 🟢 — (a) **conservation illimitée pendant la phase de test, purge à décider avant ouverture** (recommandé) ; (b) 1 an glissant ; (c) 5 ans (preuve en cas de litige sur un avis de valeur).
11. **Attribution** 🟢 — (a) **l’admin attribue ; un expert embauché peut aussi « prendre » un dossier non attribué** (recommandé) ; (b) prise libre pour tous les experts (partenaires compris) ; (c) attribution automatique (tourniquet).
12. **Demandes de services d’EPIC-08 (shooting, diagnostics, rappel Premium)** 🟢 — (a) **hors EPIC-12 : runbook SQL, puis un onglet « Demandes » dans une version suivante du back-office** (recommandé) ; (b) intégrées dès EPIC-12 (tranche en plus) ; (c) gérées par e-mail / tableur.

**Bloquantes pour coder EPIC-12 : Q1 (technologie), Q4 (rôles), Q6 (périmètre partenaire), Q7 (certification partenaire).**

---

## Journal d’exécution

- 2026-10-03 : plan rédigé (aucun code), EPIC-12 créé (📋), README mis à jour.

## Arbitrages du porteur de projet (2026-10-03) — prévalent sur le reste du plan
- Q1 : **Flutter web dans le dépôt**. Q4 : **table `staff_members`** (TOTP obligatoire). Q6 : partenaires limités aux **dossiers assignés** (initiales + commune, pas de pièce d'identité). Q7 : le partenaire **soumet**, un expert interne ou l'admin **certifie**.
- Développement après EPIC-11 et EPIC-08.
