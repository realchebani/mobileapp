# EPIC-08 · Formules & mise en vente (V10, V11, V11a, V11b, V11c) — plan d’implémentation

> Date : 2026-10-03. Statut : **livré (phase de test)** — voir le journal d’exécution et les choix par défaut en fin de document.
> Sources lues : `CLAUDE.md`, `docs/decisions.md`, `docs/epics/*.md`, [spec V8b → V19](2026-10-01-parcours-vendeur-v8b-v19.md) (§3 V10–V11c, §4.2–4.3, §5.3–5.5, §6 EPIC-08, §7, §9), [plan multi-biens](2026-10-02-multi-biens.md), plan EPIC-15 « Photos du bien » (branche `feat/epic-15-photos`, §4.6 « point d’accroche V11a »), `supabase/migrations/*` (jusqu’à `*_room_photos.sql` d’EPIC-15), `lib/seller_space/**`, `packages/sale_repository`, maquettes `ChoixOffre`, `ActivationEssentiel`, `GestionPremium`, `GestionExpert`, `GestionEssentiel`, `Dashboard` (`scratchpad/seller-design-next/project/*.dc.html`).
> Plans frères (même date) : [Coffre-fort & compte](2026-10-03-coffre-fort-et-compte.md) (EPIC-11), [Back-office expert](2026-10-03-back-office-expert.md) (EPIC-12).

---

## 0. Contexte et périmètre

Aujourd’hui (main, 2026-10-02) : un vendeur a jusqu’à 5 biens (EPIC-13), éventuellement regroupés en **lots de vente** (`property_lots`, mode `ensemble` ou `ensemble_ou_separe`) ; chaque bien est certifié séparément par l’équipe (fonctions `staff_*`, runbook) ; V9 affiche « Mettre mon bien en vente » avec un message « bientôt » ; V9b a un bouton « Mettre en vente à {valeur} » inactif. EPIC-15 (en cours) ajoute les photos par pièce (`room_photos`, écran de prise de vue avec contrôles qualité, suggestions IA) et prévoit sa réutilisation à la mise en vente.

**Dans le périmètre d’EPIC-08** :
- V10 : choix de la formule (L’Essentiel 1 %, Le Premium 1 %, L’Expert 3 %) pour **un bien certifié ou un lot** dont tous les biens sont certifiés ;
- V11 (Essentiel), V11b (Premium), V11c (Expert) : activation, **mandat en signature de test** (case + signature dessinée), demandes de services (shooting, diagnostics, mise en place Premium) sans paiement ;
- V11a : préparation et **mise en ligne dans Realesty uniquement** (photos, description, prix, publication), avec **réutilisation de la capture photo d’EPIC-15** ;
- retrait de la vente (résiliation « en un clic ») ; notifications in-app des étapes ; fonctions `staff_*` + runbook pour ce que l’équipe fait (vérifier l’identité, traiter les demandes, publier une vente Expert).

**Hors périmètre** : paiements (aucun en v1), signature électronique qualifiée, diffusion sur les portails, V11a-2 / V11a-3 (visite virtuelle), retouche IA et home staging réels (préférences seulement), V12 créneaux (EPIC-09), V12b / V15 / V16 / V17 (EPIC-09 / EPIC-10), côté acquéreur (la vente publiée n’est visible de personne tant que l’app acquéreur n’existe pas, sauf l’aperçu vendeur).

## 1. Décisions déjà prises (rappel, à ne pas rediscuter)

| Décision | Source | Conséquence ici |
|---|---|---|
| **Paiements : plus tard, aucun paiement en v1** | `decisions.md` 2026-10-01 | Pas d’IBAN ni de prélèvement : la carte SEPA de V11b devient une demande « Un conseiller vous appelle » ; les options à la carte créent des demandes traitées hors app. |
| **Mandat : signature de test** (case à cocher + signature dessinée), **tests internes uniquement**, montage juridique **à faire valider avant tout vrai vendeur** | `decisions.md` 2026-10-01 | Toutes les formules ont la même étape mandat : case + `SignaturePad`. Chaque mandat porte `is_test = true` et un PDF filigrané « SPÉCIMEN ». Accès restreint (Q1). |
| **Certification par un mini back-office web** (expert embauché + experts partenaires) | `decisions.md` 2026-10-01, EPIC-12 | La vérification d’identité (V11c) et le traitement des demandes sont des actions d’équipe : fonctions `staff_*` maintenant, boutons du back-office ensuite (plan EPIC-12). |
| **Notifications dans l’app uniquement** | `decisions.md` 2026-10-01 | Mandat signé, annonce publiée, identité vérifiée, demande traitée → lignes `notifications`. |
| **Une branche et une PR par epic** | `decisions.md` 2026-10-01 | Branche `feat/epic-08-mise-en-vente`, worktree dédié. |
| **Plusieurs biens & lots** (EPIC-13) : lot vendu « ensemble » ou « ensemble ou séparément » ; « estimation et future annonce possibles sur le lot » ; certification **par bien** | `decisions.md` 2026-10-02, EPIC-13 Q3 / Q8 | Une vente porte sur **un bien ou un lot** (§2.1). |
| **Photos (EPIC-15)** : une seule capture pour l’expert et l’annonce ; l’outil doit être **proposé à la mise en vente** si le vendeur ne l’a pas fait dans le tunnel | `decisions.md` 2026-10-02 | Le gestionnaire de photos d’annonce reprend les `room_photos` et ouvre l’écran de prise de vue d’EPIC-15 (§4.6). |
| IA : via OpenRouter / Edge Functions seulement ; **l’IA formule, n’invente aucun chiffre** | `CLAUDE.md` | Description d’annonce : modèle déterministe en v1, IA en option (Q10). |
| V9 : « Mettre en vente » visible avec un message « bientôt » jusqu’à EPIC-08 | `decisions.md` 2026-10-02 (à valider) | Remplacé par l’ouverture de V10. |

## 2. Modèle de données — migration `AAAAMMJJhhmmss_mise_en_vente.sql`

Additive, `text + check`, triggers `seller_tunnel_set_updated_at`, RLS propriétaire seul, **aucune écriture directe des colonnes d’état** (transitions par RPC `security definer`, `set search_path = ''`, contrôle de `auth.uid()` et de l’état courant).

### 2.1 `sales` — une vente = un bien **ou** un lot

La spec V8b–V19 proposait `property_sales` (une vente par bien). EPIC-13 permet de vendre un lot : on généralise.

| Colonne | Type / règle |
|---|---|
| `id` | uuid pk (choisi par l’app, insert rejouable — même pattern que `createProperty`) |
| `owner_id` | uuid not null default `auth.uid()` → `auth.users` on delete cascade |
| `property_id` | uuid null → `properties` on delete cascade |
| `lot_id` | uuid null → `property_lots` on delete cascade |
| | `check (num_nonnulls(property_id, lot_id) = 1)` |
| `formula` | text not null check in (`essentiel`, `premium`, `expert`) |
| `stage` | text not null default `plan_chosen` check in (`plan_chosen`, `mandate_signed`, `published`, `withdrawn`) — EPIC-10 ajoutera `under_offer`, `under_compromis`, `sold` |
| `asking_price_eur` | int check 1 000 – 100 000 000 (null tant que non saisi ; pré-rempli à la valeur certifiée, ou à la somme des valeurs d’un lot) |
| `listing_title` | text ≤ 120 (généré, modifiable) |
| `listing_description` | text ≤ 2 000 |
| `description_source` | text check in (`template`, `ai`, `seller`) |
| `ai_retouch_wanted`, `home_staging_wanted` | bool not null default false (préférences seulement en v1, Q9) |
| `is_test` | bool not null default true (Q1) |
| `formula_chosen_at`, `mandate_signed_at`, `published_at`, `withdrawn_at` | timestamptz |
| `withdraw_reason` | text ≤ 300 |
| `created_at`, `updated_at` | |

Index et invariants :
- `unique (property_id) where stage <> 'withdrawn'` et `unique (lot_id) where stage <> 'withdrawn'` : une seule vente active par bien et par lot.
- Trigger `sales_check_target` (BEFORE INSERT / UPDATE de `property_id`, `lot_id`) : cible appartenant à `owner_id` ; bien `certified` ; lot dont **tous** les biens sont `certified` (Q3) ; un bien membre d’un lot `ensemble` ne peut pas être vendu seul ; un bien ne peut pas avoir de vente active si son lot en a une, et inversement (Q2).
- `property_lot_is_frozen` (EPIC-13) est **recréée** pour aussi figer un lot dont un bien ou le lot lui-même a une vente active (plus d’ajout / retrait de membre, ni de changement de mode).
- RLS : `select` propriétaire. `update` propriétaire limité par **grant de colonnes** à (`asking_price_eur`, `listing_title`, `listing_description`, `description_source`, `ai_retouch_wanted`, `home_staging_wanted`) et par une politique `stage in ('plan_chosen', 'mandate_signed', 'published')`. Aucun `insert` / `delete` direct : RPC.
- Prix modifiable après publication (maquette : « Modifiable à tout moment, même après publication »).

### 2.2 `mandates` et `mandate_signatures`

`mandates` : `id`, `sale_id` → `sales` on delete cascade, `formula`, `kind` check in (`exclusif_sans_engagement`, `exclusif_3_mois`), `terms_version` text not null (ex. `test-2026-10`), `presentation_price_eur` int, `fee_rate` numeric(4,2) (1.00 / 3.00), `duration_months` smallint null (3 pour Expert), `status` check in (`signed`, `terminated`), `is_test` bool not null default true, `document_path` text (PDF généré, bucket `sale-documents`), `document_sha256` text, `signed_at`, `terminated_at`, `created_at`. Une ligne par signature de mandat (une nouvelle après un retrait + nouvelle vente). Lecture propriétaire ; aucune écriture client.

`mandate_signatures` : `id`, `mandate_id`, `signer_user_id` (= `auth.uid()`), `property_owner_id` null → `property_owners` (propriétaire n° 1 du bien ou du bien principal du lot), `signer_name` text, `method` check in (`drawn_test`, `offline`), `signature_path` text (PNG, bucket `mandate-signatures`), `accepted_terms` bool not null, `signed_at`, `user_agent` text ≤ 200, `app_version` text ≤ 40. Lecture propriétaire ; écriture par RPC (`drawn_test`) ou par l’équipe (`offline`, co-propriétaires hors app — Q4).

`property_owners` : + `identity_verified_at timestamptz`, `identity_verified_by uuid` (aucun grant : équipe seulement). Utilisé par V11c (Expert) et affiché dans V19 (EPIC-11).

### 2.3 `sale_requests` — services demandés (sans paiement)

`id`, `sale_id`, `kind` check in (`premium_setup`, `shooting_photo`, `shooting_photo_video`, `diagnostics`), `diagnostics text[]` (sous-ensemble de `dpe`, `electricite`, `gaz`, `amiante`, `plomb`, `termites`, `erp`), `preferred_slots timestamptz[]` (≤ 3), `status` check in (`requested`, `scheduled`, `done`, `cancelled`), `scheduled_at`, `price_eur_ttc` int (affichage, tarif indicatif — Q14), `staff_note` text ≤ 500 (sans grant), `created_at`, `updated_at`. Lecture propriétaire ; création et annulation par RPC ; le reste par l’équipe.

### 2.4 `listing_photos` + bucket `listing-media`

`id` (choisi par l’app), `sale_id`, `property_id` (bien membre de la vente, utile pour un lot), `room_id` null → `rooms` (on delete set null), `source_room_photo_id` null → `room_photos` (on delete set null ; trace de la copie), `storage_path` unique (`<owner id>/<sale id>/<photo id>.jpg`), `width`, `height`, `size_bytes`, `sort_order`, `is_cover` bool, `caption` ≤ 80, `created_at`, `updated_at`.
- `unique (sale_id) where is_cover` ; au plus **40 photos par vente** (trigger avec verrou consultatif, comme `room_photos_check_limits`).
- RLS : propriétaire CRUD tant que `stage in ('plan_chosen', 'mandate_signed', 'published')` ; politique restrictive sur `storage_path like auth.uid() || '/' || sale_id || '/%'`.
- Bucket **`listing-media`** privé, 15 Mo, JPEG / PNG / HEIC ; politiques Storage : lecture du dossier `<uid>/` ; insert / delete si la vente du 2ᵉ segment appartient à l’utilisateur et est active. Les photos choisies parmi les `room_photos` sont **copiées** dans ce bucket (copie Storage inter-bucket faite par l’app : lecture autorisée sur la source, écriture sur la destination — Q12), pour que l’annonce vive indépendamment du dossier verrouillé et puisse plus tard avoir des dérivés publics.

### 2.5 Buckets de documents générés

- **`mandate-signatures`** (privé, PNG, 1 Mo) : `<owner id>/<sale id>/<signature id>.png` ; insert propriétaire (pas d’update / delete) ; lecture propriétaire.
- **`sale-documents`** (privé, PDF, 20 Mo) : mandats générés (puis offres, compromis : EPIC-10) ; écrit **uniquement** par Edge Function (service role) ; lecture propriétaire `<owner id>/…`. Le coffre-fort (EPIC-11) les liste dans « Mandats & visites ».

### 2.6 Notifications

`notifications.kind` est aujourd’hui un `check in ('review_started', 'valuation_certified')`. Chacun des trois plans frères en ajoute : chaque migration remplace le check, **de façon idempotente**, par un contrôle de format `kind ~ '^[a-z][a-z_]{2,39}$'` (`drop constraint if exists` + `add constraint`), ainsi l’ordre de fusion des epics est indifférent ; l’app lit tout type inconnu comme `other`. Types EPIC-08 : `mandate_signed`, `listing_published`, `identity_verified`, `sale_request_updated`, `sale_withdrawn`. Route : `/vendeur/ventes/<sale id>` (ou `…/annonce`).

### 2.7 RPC (exécutables par `authenticated`, `security definer`)

| Fonction | Contrôles | Effet |
|---|---|---|
| `choose_formula(p_sale_id uuid, p_property_id uuid, p_lot_id uuid, p_formula text) returns uuid` | cible à l’utilisateur, éligible (§2.1) ; si une vente active existe : seulement en `plan_chosen` (changement de formule) | crée la vente (`plan_chosen`, prix pré-rempli = valeur certifiée ou somme du lot, `is_test`) ou change sa formule ; rejouable avec le même `p_sale_id` |
| `sign_test_mandate(p_sale_id uuid, p_terms_version text, p_signature_path text, p_accepted boolean, p_user_agent text, p_app_version text) returns uuid` | vente à l’utilisateur en `plan_chosen` ; `p_accepted` ; objet PNG présent au bon chemin ; Expert : `identity_verified_at` du propriétaire n° 1 non nul ; pièce d’identité présente pour toutes les formules (Q5) | crée `mandates` (`signed`, `is_test`) + `mandate_signatures` (`drawn_test`), `stage = mandate_signed`, notification ; renvoie l’id du mandat (l’app appelle ensuite `render-mandate`) |
| `request_sale_service(p_request_id uuid, p_sale_id uuid, p_kind text, p_diagnostics text[], p_preferred_slots timestamptz[]) returns uuid` | vente active ; pas deux demandes `requested` du même type | crée la demande (`requested`), prix indicatif depuis une table de constantes |
| `cancel_sale_request(p_request_id uuid)` | demande `requested` de l’utilisateur | `cancelled` |
| `publish_listing(p_sale_id uuid)` | formule `essentiel` / `premium`, `stage = mandate_signed` ; prix ; description non vide ; **≥ N photos dont une couverture** (Q11) | `published`, `published_at`, notification ; erreurs typées (`missing_photos`, `missing_description`, `missing_price`, `mandate_not_signed`) mappées en l10n |
| `unpublish_listing(p_sale_id uuid)` | `published` | retour à `mandate_signed` (annonce hors ligne, modifiable) |
| `withdraw_sale(p_sale_id uuid, p_reason text)` | stage ∉ {`withdrawn`} (EPIC-10 : refusé après offre acceptée) | `withdrawn`, mandat `terminated`, demandes `requested` annulées, notification ; le lot est dégelé si plus rien ne le fige |

Fonctions équipe (`security invoker`, exécution retirée à `public`, `anon`, `authenticated` ; SQL Editor en attendant EPIC-12, qui les enveloppera dans ses RPC `bo_*`) :
`staff_verify_identity(p_property_owner_id)`, `staff_update_sale_request(p_request_id, p_status, p_scheduled_at, p_note)`, `staff_publish_expert_sale(p_sale_id)` (formule Expert : publication par l’équipe / l’agent), `staff_record_offline_signature(p_mandate_id, p_property_owner_id, p_signer_name)`. Runbook **`docs/runbooks/suivre-une-vente.md`**.

### 2.8 Sonde RLS (bloc `DO` annulé, `supabase db query --linked`)
Propriétaire : choisit une formule sur un bien certifié ✔, sur un brouillon ✘, sur un bien d’un autre ✘, sur un bien d’un lot `ensemble` ✘ ; lot non entièrement certifié ✘ ; deux ventes actives ✘ ; signature sans case ✘, sans PNG ✘, Expert sans identité vérifiée ✘ ; publication sans photo ✘ ; modification de `stage` / `is_test` par `update` ✘ ; photo d’annonce dans le dossier d’un autre ✘ ; écriture dans `sale-documents` ✘ ; lot figé après la vente ✔ ; autre utilisateur et `anon` ne voient rien.

## 3. Fonctions serveur (Edge Functions)

- **`render-mandate`** (nouvelle, Deno, `pdf-lib` MIT) — Q6 : POST `{ mandate_id }` avec le JWT de l’appelant ; vérifie par RLS (client avec ce JWT) que le mandat appartient à l’appelant et n’a pas encore de PDF ; construit le PDF depuis un **modèle versionné** (`_shared/mandate/templates/test-2026-10.ts` : parties = propriétaires du bien ou du bien principal, désignation du bien / des biens du lot, prix de présentation, honoraires, durée, exclusivité, conditions de résiliation), insère la signature PNG, l’horodatage, l’agent utilisateur, la version des conditions, et un **filigrane « SPÉCIMEN — signature de test sans valeur juridique »** sur chaque page ; calcule le SHA-256 ; écrit dans `sale-documents` puis `mandates.document_path` / `document_sha256` avec le service role. Idempotente (renvoie le chemin existant). Tests Deno : contenu, filigrane, refus d’un mandat d’autrui.
- **`generate-listing-description`** (facultative, Q10 option b) : client OpenRouter d’EPIC-06, faits seulement issus du dossier, chiffres vérifiés comme pour l’estimation (`_shared/estimation` : contrôle des nombres de la sortie contre les faits fournis), `OPENROUTER_MODEL_LISTING`, quota par vente. **Non prévue en v1** si Q10 = (a).
- Pas de fonction de paiement, pas de webhook.

## 4. Écrans et parcours

Routes (enfants de `/vendeur`, `parentNavigatorKey: sellerNavigatorKey`, plein écran au-dessus des onglets, comme le tunnel) — la vente a son identifiant, ce qui couvre bien et lot :

| Écran | Route | Maquette |
|---|---|---|
| V10 Choix de la formule | feuille modale sur V9 / V9b / fiche de lot (pas de route) | `ChoixOffre.dc.html` |
| Accueil de la vente (aiguillage selon formule et étape) | `/vendeur/ventes/<saleId>` | — (redirige) |
| V11 Activation L’Essentiel | `/vendeur/ventes/<saleId>/essentiel` | `ActivationEssentiel.dc.html` |
| V11b Activation Premium | `/vendeur/ventes/<saleId>/premium` | `GestionPremium.dc.html` |
| V11c Identité & mandat Expert | `/vendeur/ventes/<saleId>/expert` | `GestionExpert.dc.html` |
| Signature du mandat (feuille partagée V11 / V11b / V11c) | feuille | bloc signature de `GestionExpert` |
| V11a Mise en ligne | `/vendeur/ventes/<saleId>/annonce` | `GestionEssentiel.dc.html` |
| Gestionnaire de photos d’annonce | `/vendeur/ventes/<saleId>/annonce/photos` | **absent du canevas** |
| Aperçu de l’annonce | `/vendeur/ventes/<saleId>/annonce/apercu` | **absent du canevas** (icône « Aperçu » de V11a) |

`AppRoutes.sellerSale(id)`, `sellerSaleListing(id)`, … ; un `SaleRouteScope` (même rôle que `PropertyRouteScope`) fournit le `SaleCubit` de la vente (vente, mandat, demandes, photos, valeurs certifiées des biens), gère chargement / échec / introuvable → `/vendeur`, et **redirige selon l’étape** (ex. V11a avant signature → écran de la formule ; vente retirée → V9). Les conditions d’entrée reprennent la spec §1.4 en remplaçant `property_sales` par `sales`.

### 4.1 Points d’entrée (V9, V9b, fiche de lot)
- V9 certifié, sans vente : ActionCard accent « Mettre mon bien en vente » → V10 (remplace le message « bientôt »). V9b « Mettre en vente à {valeur} » → V10.
- Bien membre d’un lot : le bouton du bien ouvre V10 **pour le lot** si le lot est `ensemble` (texte « Mettre le lot en vente ») ; pour `ensemble_ou_separe`, selon Q2.
- Fiche du lot (`/vendeur/lots/<id>`) : « Mettre le lot en vente » quand tous les biens sont certifiés, sinon « Disponible quand tous les biens seront certifiés (2/3) ».
- Vente active : V9 remplace l’ActionCard par une **carte « Ma vente »** (badge de formule, étape : « Mandat à signer », « Annonce en préparation », « En ligne depuis le … », action principale vers l’écran courant, menu « Retirer de la vente »). Variante non dessinée → construite avec `ActionCard` / `KeyValueRow` (écart de maquette à signaler).
- « Mes biens » : statut « En vente » / « Mandat signé » sur la ligne du bien (et du lot).

### 4.2 V10 · Choix de la formule (`OfferChoiceSheet`)
Conforme à la spec §3 V10 : `PlanTabs` (onglet par défaut selon Q8), `OfferPlanCard` × 3 (textes verbatim, apostrophes typographiques), commission estimée `round(valeur × taux, -1)` avec `frenchNumber` (valeur = valeur certifiée du bien ou somme du lot). CTA → `choose_formula` → push de l’écran de la formule. Lien « Comparer les 3 formules » masqué en v1 (Q8). Bandeau discret « Phase de test : aucun paiement, mandat de test » tant que `is_test`.

### 4.3 V11 · L’Essentiel (`EssentielActivationPage`)
Reprend la maquette, avec :
- carte mandat : récapitulatif + case « J’ai lu et j’accepte les conditions du mandat L’Essentiel » + bouton « Signer le mandat en ligne » → **feuille de signature** (§4.6) ; état signé : « Mandat signé le … » + « Voir le mandat (PDF) » ; pièce d’identité absente : `InlineBanner.warning` + lien vers V18 Identité (EPIC-11 ; à défaut V7 du bien en lecture → message) ;
- carte photos : interrupteurs « Retouche automatique IA » / « Home staging virtuel » = préférences (`Bientôt`, Q9) ; « Prendre mes photos avec l’assistant » → gestionnaire de photos d’annonce ;
- options à la carte : « Ajouter » → `request_sale_service` (« Un conseiller vous recontacte ») ; « J’ai déjà mes diagnostics : les importer » → V18 Énergie (EPIC-11) ;
- lien upsell Premium (change la formule tant que `plan_chosen`) ;
- CTA collant « Activer et préparer mon annonce » : refusé tant que le mandat n’est pas signé (erreur affichée, défilement — motif du tunnel) → V11a.

### 4.4 V11b · Le Premium (`PremiumActivationPage`)
- Étape 0 **Mandat** (même carte que V11 ; la maquette n’en a pas — écart signalé).
- Carte « Prélèvement SEPA » **remplacée** par `InlineBanner.info` « Un conseiller Realesty vous appelle pour mettre en place votre formule Premium. » + bouton « Être rappelé » (`premium_setup`).
- Shooting : `SelectableCard` Photo / Photo + vidéo, 3 créneaux proposés (Q11), confirmation « Demande envoyée » puis « Shooting confirmé le … » quand l’équipe planifie.
- Diagnostics : présélection par **règles déterministes** (`diagnostics_rules.dart`, pures et testées : DPE + ERP toujours ; électricité / gaz si installation > 15 ans ou inconnue ; amiante si construit avant 07/1997 ; plomb avant 1949 ; termites « à vérifier ») ; libellé « Présélection d’après votre audit (…) » (Q9) ; bandeau « Aucun diagnostic valide trouvé dans votre coffre-fort » si aucun document `diagnostics` / `dpe`.
- CTA « Continuer » → **V11a** (Q7 : l’annonce avant les créneaux d’EPIC-09).

### 4.5 V11c · L’Expert (`ExpertMandatePage`)
- Chronologie (`Timeline` promue de V8 dans `lib/ui`) : « Identité vérifiée » (propriétaires, `identity_verified_at`) → « Mandat de vente » (« À signer ») → « Agent assigné » (« Sous 24 h après signature », Q17).
- Identité non vérifiée : signature désactivée + « Votre pièce d’identité doit être vérifiée par notre équipe avant la signature. » ; pièce absente → lien V18.
- « Lire » : conditions du mandat (texte versionné embarqué, même modèle que le PDF) avant signature ; PDF signé après.
- Lignes prix de présentation / honoraires 3 % / durée 3 mois / exclusivité ; `SignaturePad` + case ; CTA « Signer le mandat » → retour V9 avec la carte « Ma vente · Un agent vous contacte » (V15 = EPIC-10).

### 4.6 Signature du mandat de test (feuille partagée `MandateSignatureSheet`)
Titre « Signature du mandat », bandeau **« Signature de test — sans valeur juridique »**, résumé du mandat, signataire « {Prénom Nom} (vous) », autres propriétaires « signeront hors de l’application » (Q4), case d’acceptation, `SignaturePad` (130 px, « Signez du bout du doigt » · « Effacer »), bouton « Signer ». Envoi : PNG (`toImage`) → `mandate-signatures` → `sign_test_mandate` → `render-mandate` (en arrière-plan, nouvelle tentative au prochain affichage si elle échoue). Délai 15 s, erreurs en snackbar, double tap sans effet (ids choisis par l’app).

### 4.7 V11a · Mise en ligne (`ListingEditorPage`)
- Badge de formule correct (`L’Essentiel · 1 %` ou `Premium · 1 %` — écart maquette) + `Brouillon` / `En ligne`.
- Photos : bande des 4 premières (+N), compteur, « Gérer les photos » → gestionnaire ; interrupteurs retouche / home staging (préférences, `Bientôt`).
- Carte « Visite virtuelle 360° » **masquée** (V11a-2/3 différés).
- Description : `listing_title` + texte généré par `ListingDescriptionTemplate` (pur, Dart, faits du dossier : type, surface, pièces, terrain, équipements, cadre de vie déclaré ; un lot décrit chaque bien) ; badge « Généré automatiquement » (Q9) → « Modifié par vous » ; feuille d’édition 2 000 caractères.
- Prix : champ + `PriceRangeSlider` sur la fourchette certifiée (lot : somme des bornes) ; badge « Dans la fourchette » / « Hors fourchette » ; commission en direct ; ligne « Diffusion : Realesty » ; « Visites : Pass Visite requis » masquée tant qu’EPIC-09 n’existe pas.
- CTA « Publier mon annonce » (le libellé « …et ouvrir mes créneaux » arrive avec EPIC-09) → `publish_listing` → état « En ligne » + notification ; « Retirer de la ligne » (`unpublish_listing`) en bas quand publiée.
- Formule Expert : pas de V11a pour le vendeur (l’agent prépare l’annonce, `staff_publish_expert_sale`).

### 4.8 Gestionnaire de photos d’annonce (`ListingPhotosPage`, non dessiné)
- Sections par pièce (biens du lot groupés par bien) avec les **photos du dossier** (`room_photos`, URL signées) : toucher = « Utiliser dans l’annonce » (copie dans `listing-media` + ligne `listing_photos`), badges d’EPIC-15 (« Personne visible », « Floue »…) et rappel « objets personnels à ranger » issu de `room_photos.analysis` ; une photo signalée « Personne visible » ne peut pas être choisie (Q12).
- « Prendre de nouvelles photos » par pièce → **écran de prise de vue d’EPIC-15** (contrôles qualité sur l’appareil, réduction 2 048 px, JPEG) en mode « annonce » : les photos gardées vont dans `listing-media` (pas dans `room_photos`, verrouillées après l’envoi). « Photothèque » idem.
- Bande « Annonce » : ordre (glisser), couverture (étoile), légende courte, retirer. Compteur « 7 photos · minimum 5 » (Q11).
- Exige d’EPIC-15 une API de capture **découplée du stockage** : `Future<List<ProcessedPhoto>> capturePhotos(context, {required String title})` (fichiers traités + contrôles) ; si EPIC-15 livre l’écran couplé à `room_photos`, la tranche O8 en extrait cette API (coordination, §6).

### 4.9 Aperçu de l’annonce (non dessiné)
Lecture seule « Ce que verront les acquéreurs » : couverture + galerie, titre, prix, commune (adresse selon Q13), surfaces / pièces, description. Sert aussi de base à la future fiche acquéreur (A-écrans).

### 4.10 Retrait de la vente
Menu de la carte « Ma vente » (V9) et, après EPIC-11, « Ma formule » dans Compte (Q15) → feuille de confirmation intégrée (pas de `confirm()`) : conséquences (« Votre annonce sera retirée, le mandat de test résilié ») + motif facultatif → `withdraw_sale`.

## 5. Données côté app

- **`packages/sale_repository`** (existe : avis de valeur, notifications) + `SaleRepository` : `getActiveSale(propertyId | lotId)`, `listSales()`, `chooseFormula`, `signTestMandate` (upload PNG + RPC), `renderMandate` (`functions.invoke`), `mandatePdfUrl`, `requestService` / `cancelRequest`, `updateListing(patch)`, `publish` / `unpublish` / `withdraw`, `listingPhotos` (liste, URL signées, `addFromRoomPhoto` (copie Storage), `upload`, `reorder`, `setCover`, `delete`) ; modèles `Sale`, `SaleFormula` (taux, frais, libellés — constantes uniques, miroir des contrôles SQL), `SaleStage`, `Mandate`, `SaleRequest`, `ListingPhoto` ; échecs typés (`SaleEligibilityFailure`, `PublishFailure(reasons)`…).
- `AppNotificationKind` : nouveaux types (§2.6).
- `lib/seller_space/sale/` : `SaleRouteScope`, `SaleCubit`, `offer_choice/`, `essentiel/`, `premium/`, `expert/`, `mandate/` (feuille de signature), `listing/` (éditeur, photos, aperçu, modèle de description), `widgets/` (`SaleCard` de V9). Barrel `seller_space.dart` mis à jour.
- Design system (`lib/ui/components/` + galerie + tests) : `SignaturePad`, `OfferPlanCard` + `PlanTabs`, `PriceRangeSlider`, `RealestySwitch` / `SwitchRow`, `Timeline` (promue de `submitted_timeline.dart`).
- l10n : préfixes `offerChoice*`, `activation*`, `premium*`, `expertMandate*`, `mandate*`, `listing*`, `listingPhotos*`, `sale*` (écriture lecture-modification du JSON puis `flutter gen-l10n`, sérialisée entre agents).

## 6. User stories (EPIC-08)

- **US-08.1 · Choisir ma formule (V10)** — *En tant que vendeur d’un bien certifié (ou d’un lot entièrement certifié), je veux comparer les trois formules et en choisir une.*
  - Feuille à 3 onglets, contenus du design, commission estimée à partir de la valeur certifiée (ou de la somme du lot).
  - Le choix crée ma vente ; je peux changer de formule tant que le mandat n’est pas signé.
  - Un bien d’un lot « ensemble » ne se vend qu’avec son lot ; un lot n’est proposé que si tous ses biens sont certifiés.
  - Phase de test : un bandeau indique l’absence de paiement et le mandat de test ; l’accès suit Q1.
- **US-08.2 · Signer mon mandat de test** — *En tant que vendeur, je veux accepter et signer mon mandat dans l’app.*
  - Case obligatoire + signature dessinée ; erreur claire si l’une manque.
  - Signature horodatée, version des conditions, agent utilisateur conservés ; PDF « SPÉCIMEN » généré et consultable (puis rangé dans le coffre-fort, EPIC-11).
  - Pièce d’identité exigée (lien pour l’ajouter) ; pour L’Expert, identité vérifiée par l’équipe.
  - Les co-propriétaires sont indiqués « signeront hors de l’application » (Q4).
- **US-08.3 · Activer L’Essentiel (V11)** — récapitulatif, mandat, préférences photo, options à la carte transformées en demandes (« Un conseiller vous recontacte »), « Activer et préparer mon annonce » seulement après signature.
- **US-08.4 · Activer Le Premium (V11b)** — demande de rappel à la place du prélèvement ; choix du shooting et de 3 créneaux souhaités ; diagnostics présélectionnés par des règles explicites, modifiables ; étape mandat ; puis V11a.
- **US-08.5 · Confier la vente à L’Expert (V11c)** — chronologie identité → mandat → agent ; signature désactivée tant que l’identité n’est pas vérifiée ; après signature, V9 affiche « Un agent vous contacte sous 24 h ».
- **US-08.6 · Choisir et prendre les photos de mon annonce** — je réutilise les photos de mes pièces (sauf celles où une personne est visible), j’en prends de nouvelles avec l’assistant photo (contrôles qualité), je choisis l’ordre et la couverture ; 40 photos au plus.
- **US-08.7 · Préparer et publier mon annonce (V11a)** — description générée sans chiffre inventé et modifiable ; prix avec position dans la fourchette et commission en direct ; « Publier » refusé avec la liste de ce qui manque ; aperçu « ce que verront les acquéreurs » ; annonce visible dans Realesty seulement (diffusion « Realesty »).
- **US-08.8 · Suivre et retirer ma vente** — carte « Ma vente » sur V9 et statut dans « Mes biens » ; retirer avec confirmation (annonce retirée, mandat résilié) ; prix modifiable après publication ; mettre hors ligne puis republier.
- **US-08.9 · Être prévenu** — notifications in-app : mandat signé, identité vérifiée, demande planifiée, annonce publiée, vente retirée ; chacune ouvre la vente concernée.
- **US-08.10 · Traitement par l’équipe (avant EPIC-12)** — fonctions `staff_*` et runbook « Suivre une vente » : vérifier une identité, planifier / clore une demande, enregistrer une signature hors app, publier une vente Expert.

## 7. Découpage (tranches de 1 à 2 h, un agent codeur chacune)

| # | Tranche | Fichiers possédés | Dépend de |
|---|---|---|---|
| O0 | DS : `SignaturePad`, `OfferPlanCard` / `PlanTabs`, `PriceRangeSlider`, `RealestySwitch` / `SwitchRow`, `Timeline` (+ galerie, tests) | `lib/ui/components/<nouveaux>.dart`, `lib/ui/ui.dart`, `lib/ui/gallery/**`, `lib/seller_tunnel/steps/submitted/widgets/submitted_timeline.dart` (remplacé par l’import) | — |
| O1 | Migration `*_mise_en_vente.sql` (§2), essai en transaction annulée, sonde RLS, `db push` ; runbook `suivre-une-vente.md` | `supabase/migrations/*_mise_en_vente.sql`, `docs/runbooks/suivre-une-vente.md` | Q2, Q3, Q12 tranchées |
| O2 | `render-mandate` + modèle `_shared/mandate/` + tests Deno, déploiement | `supabase/functions/render-mandate/**`, `supabase/functions/_shared/mandate/**`, `supabase/functions/tests/render_mandate_test.ts` | O1, Q6 |
| O3 | `SaleRepository` + modèles + tests (100 %), `App` / `bootstrap` / mocks | `packages/sale_repository/**`, `lib/bootstrap.dart`, `lib/app/view/app.dart`, `test/helpers/mocks.dart` | O1 |
| O4 | Routes, `SaleRouteScope`, `SaleCubit`, carte « Ma vente » sur V9, points d’entrée V9b / lot / Mes biens, V10 | `lib/app/router/**`, `lib/seller_space/sale/{scope,cubit,offer_choice,widgets}/**`, `lib/seller_space/dashboard/**`, `lib/seller_space/report/report_page.dart` (bouton), `lib/seller_space/lot/lot_page.dart`, `lib/seller_space/my_properties/widgets/property_row.dart`, ARB `offerChoice*`, `sale*` | O0, O3 |
| O5 | Feuille de signature + V11 Essentiel | `lib/seller_space/sale/mandate/**`, `lib/seller_space/sale/essentiel/**`, ARB `mandate*`, `activation*` | O4, O2 |
| O6 | V11b Premium + `diagnostics_rules.dart` | `lib/seller_space/sale/premium/**` | O5 (carte mandat) |
| O7 | V11c Expert | `lib/seller_space/sale/expert/**` | O5 |
| O8 | Gestionnaire de photos d’annonce (réutilise EPIC-15) ; extraction éventuelle de l’API `capturePhotos` | `lib/seller_space/sale/listing/photos/**` (+ fichiers EPIC-15 de capture, après fusion d’EPIC-15) | O4, **EPIC-15 fusionné**, Q12 |
| O9 | V11a éditeur, modèle de description, aperçu, publication, retrait | `lib/seller_space/sale/listing/{editor,preview,data}/**`, ARB `listing*` | O4, O8 |
| O10 | Notifications (types, routes), parcours complet dans `test/app/view/app_test.dart`, `CLAUDE.md`, epic, journal | `packages/sale_repository/lib/src/models/app_notification.dart`, `test/app/view/app_test.dart`, docs | toutes |

Vagues : **{O0, O1}** → **{O2, O3}** → **{O4}** → **{O5, O8}** → **{O6, O7, O9}** → **{O10}**. Les écritures ARB sont sérialisées (une tranche à la fois, ou un delta par tranche fusionné par O10). Chaque tranche est contrôlée par un agent de vérification (tests, revue, rendu 390 px comparé aux maquettes).

Ordre conseillé entre epics : EPIC-11 (coffre-fort : pièce d’identité et diagnostics après verrouillage, consultation du mandat) peut précéder ou suivre ; EPIC-08 dégrade proprement (liens V18 masqués via `isRouteAvailable`). EPIC-12 n’est pas requis : les `staff_*` suffisent aux tests internes.

## 8. Risques

| Risque | Parade |
|---|---|
| Un vrai vendeur signe un mandat de test sans valeur | `is_test` partout, filigrane PDF, bandeau, accès restreint (Q1) ; ouverture conditionnée à la validation juridique (carte T / agence partenaire / signature qualifiée). |
| Modèle bien **ou** lot : cas limites (lot modifié pendant une vente, bien vendu seul puis ajouté à un lot) | Triggers `sales_check_target` + `property_lot_is_frozen` étendue ; sonde RLS dédiée ; Q2 tranchée avant O1. |
| Dépendance à EPIC-15 (capture, `room_photos`) en cours | O8 en dernière vague ; repli : sélection photothèque / appareil (image_picker) sans contrôles qualité. |
| Stockage : offre gratuite Supabase 1 Go (photos du dossier + copies d’annonce) | Photos 2 048 px JPEG ~400 Ko ; 40 photos max par annonce ; suivi dans le runbook ; passage à Supabase Pro dans le backlog (étude capture Q10). |
| PDF généré côté serveur (police, accents, taille) | `pdf-lib` + police embarquée (Hanken Grotesk) ; tests Deno sur le texte extrait. |
| Écrans non dessinés (gestionnaire de photos, aperçu, carte « Ma vente », signature 1 %) | Construits avec le design system ; listés pour le canevas (§9). |
| Promesses « IA » non tenues (retouche, home staging, présélection) | Libellés neutres (Q9), interrupteurs « Bientôt ». |
| Conflits de fichiers avec EPIC-09 / EPIC-10 (V9, routes) | Carte « Ma vente » isolée dans `sale/widgets/` ; routes de vente regroupées dans une seule fonction du routeur. |

## 9. Écarts de maquette à signaler à Claude Design
V11a badge `Premium · 1 %` figé ; Premium sans étape mandat ; V11 sans signature dessinée (décision) ; V11b va directement à V12 ; aucun écran pour : gestionnaire de photos d’annonce, aperçu de l’annonce, signature du mandat 1 %, carte « Ma vente » sur V9, mise en vente d’un lot, retrait de la vente ; straight apostrophes `L'Essentiel` / `L'Expert`.

## 10. Questions ouvertes (réponse du porteur de projet attendue)

Légende : **🔴 bloquante** (à trancher avant la tranche indiquée) · **🟢 défaut réversible** (on code l’option recommandée, changeable ensuite par une constante ou une petite tranche).

1. **Accès aux ventes pendant la phase de test** 🟢 (avant O4) — (a) **drapeau `SALES_ENABLED` dans `config/<flavor>.json` (development seulement) + `is_test` sur chaque vente et mandat** (recommandé : comme `VOICE_ENABLED`) ; (b) liste blanche en base (`sale_testers`) pour ouvrir à quelques testeurs nommés ; (c) ouvert à tout vendeur certifié avec le bandeau « test ».
2. **Vente d’un lot « ensemble ou séparément »** 🔴 (avant O1, modèle de données) — (a) **une vente porte sur un bien seul ou sur le lot entier ; pour un lot « ensemble ou séparément », v1 ne propose que la vente du lot, l’annonce mentionne « biens vendables séparément » avec la valeur de chacun** (recommandé) ; (b) vente du lot et ventes séparées en parallèle (prix par bien, offres partielles : EPIC-10 complexe) ; (c) pas de vente de lot en v1 (bien par bien seulement).
3. **Quand un lot peut-il être mis en vente ?** 🔴 (avant O1) — (a) **tous ses biens certifiés** (recommandé, cohérent avec la certification par bien) ; (b) le bien principal certifié suffit ; (c) une certification de lot dédiée (EPIC-12, plus tard).
4. **Co-propriétaires et signature (spec Q12)** 🟢 — (a) **le titulaire du compte signe pour lui ; les autres propriétaires sont listés « signeront hors de l’application », l’équipe enregistre leur signature (`offline`)** (recommandé) ; (b) le titulaire déclare signer au nom de tous ; (c) invitation des co-propriétaires par lien magique (nécessite le SMTP Brevo et des comptes membres — `property_members`).
5. **Pièce d’identité et vérification avant signature** 🟢 — (a) **pièce d’identité présente exigée pour toutes les formules, vérification par l’équipe exigée pour L’Expert seulement** (recommandé, maquettes) ; (b) vérification exigée pour toutes ; (c) aucune exigence pendant les tests internes.
6. **PDF du mandat** 🟢 (avant O2) — (a) **généré côté serveur (`render-mandate`, `pdf-lib`), filigrane « SPÉCIMEN », empreinte SHA-256** (recommandé : intégrité, réutilisable pour la vraie signature) ; (b) généré dans l’app avec le paquet `pdf` déjà présent puis déposé ; (c) pas de PDF pendant les tests (signature enregistrée en base seulement). Et : **qui rédige le texte du modèle de test ?** (proposé : texte court rédigé par nous, explicitement non contractuel).
7. **Ordre du parcours Premium (spec Q6)** 🟢 — (a) **V11b → V11a (annonce) → V12 créneaux (EPIC-09)** (recommandé) ; (b) V11b → V12 comme la maquette, annonce préparée par le coach Premium ; (c) un écran d’activation commun aux deux formules 1 %.
8. **V10 : onglet par défaut et « Comparer les 3 formules » (spec Q7)** 🟢 — onglet : (a) **Premium comme la maquette** (recommandé) ; (b) L’Essentiel (le moins cher) ; (c) la recommandation de l’agent. Comparatif : (a) **masqué en v1** (recommandé) ; (b) tableau plein écran.
9. **Mentions « IA » (spec Q9)** 🟢 — (a) garder les libellés de la maquette avec des règles / modèles déterministes ; (b) **libellés neutres (« Présélection d’après votre audit », « Généré automatiquement ») tant qu’aucun modèle ne tourne ; retouche et home staging = préférences « Bientôt »** (recommandé) ; (c) masquer ces fonctions.
10. **Description de l’annonce** 🟢 — (a) **modèle déterministe en Dart à partir du dossier, modifiable** (recommandé v1, gratuit, aucun chiffre inventé) ; (b) Edge Function OpenRouter `generate-listing-description` (faits seulement, chiffres contrôlés) ; (c) rédigée par le vendeur seul.
11. **Exigences de publication et créneaux de shooting (spec Q10)** 🟢 — photos minimum : (a) 1 ; (b) **5 dont une couverture** (recommandé) ; (c) 10 + couverture. Créneaux de shooting proposés : (a) saisis par l’équipe ; (b) **3 créneaux générés (3 prochains jours ouvrés, 10 h / 14 h), confirmés par l’équipe** (recommandé).
12. **Photos de l’annonce et photos du dossier (EPIC-15)** 🔴 (avant O1 / O8) — (a) **copie des photos choisies dans un bucket d’annonce `listing-media` + nouvelles prises de vue directement dans ce bucket** (recommandé : annonce indépendante du dossier verrouillé, futurs dérivés publics) ; (b) l’annonce référence les `room_photos` sans copie (pas de doublon, mais dossier verrouillé = impossible d’en ajouter ; suppression liée) ; (c) capture séparée pour l’annonce, sans réutiliser le dossier. Et : **exclure d’office les photos « personne visible »** (proposé : oui).
13. **Adresse affichée dans l’annonce** 🟢 (pas avant l’app acquéreur) — (a) **commune et quartier seulement, adresse exacte après visite acceptée** (recommandé, usage courant et sécurité) ; (b) rue sans numéro ; (c) adresse complète.
14. **Tarifs affichés sans paiement (spec Q4, décidé : aucun paiement)** 🟢 — (a) **montrer les montants de la maquette (299 €, 99 €/mois, 200 / 350 / 250 € TTC) comme « tarifs indicatifs, rien n’est prélevé dans l’app »** (recommandé) ; (b) masquer les montants Premium et options ; (c) retirer Le Premium en v1. **Confirmer aussi les montants.**
15. **Retrait / résiliation (spec Q18)** 🟢 — (a) **menu de la carte « Ma vente » (V9) + « Ma formule » dans Compte (EPIC-11) ; retrait = annonce retirée, mandat résilié, demandes annulées, photos d’annonce conservées** (recommandé) ; (b) seulement en contactant l’équipe ; (c) Compte seulement. L’Expert (3 mois) : retrait anticipé autorisé en test (proposé) ou refusé avant échéance.
16. **Changer de formule après signature** 🟢 — (a) **retirer la vente puis en choisir une nouvelle (nouveau mandat)** (recommandé) ; (b) passage direct Essentiel ↔ Premium avec un avenant ; (c) impossible en v1.
17. **L’Expert en v1 : qui est l’agent ?** 🟢 — (a) **l’équipe Realesty joue l’agent ; V9 affiche « Un agent vous contacte sous 24 h », les contacts arrivent avec EPIC-10 (`sale_contacts`)** (recommandé) ; (b) une agence partenaire réelle dès maintenant ; (c) formule Expert masquée en v1.
18. **Types de biens éligibles** 🟢 — (a) **tout bien (ou lot) certifié, quel que soit le type** (recommandé) ; (b) exclure garage / dépendance seuls (commission trop faible : minimum de commission ?) ; (c) maison / appartement seulement.

### 10.1 Les 18 questions de la spec V8b–V19 (§7) : où elles en sont

| # spec | Sujet | Statut |
|---|---|---|
| Q1 | Qui certifie, avec quel outil | **Tranchée** (§9 spec) : back-office web → plan EPIC-12 |
| Q2 | Format du rapport V9b | **Tranchée** : structuré + PDF (EPIC-07) |
| Q3 | Brouillon et barre d’onglets | **Tranchée**, livrée (EPIC-07) |
| Q4 | Paiements | **Tranchée** : aucun en v1 → ici Q14 (affichage des tarifs) |
| Q5 | Mandat (juridique) | **Tranchée** : signature de test → ici Q4, Q5, Q6 |
| Q6 | Ordre Premium | **Ici Q7** |
| Q7 | V10 par défaut / comparatif | **Ici Q8** |
| Q8 | Offres sous L’Expert | EPIC-10 (hors de ce plan) |
| Q9 | Mentions « IA » | **Ici Q9** (+ Q10 description) |
| Q10 | Exigences de publication | **Ici Q11** |
| Q11 | Notifications | **Tranchée** : in-app seulement |
| Q12 | Co-propriétaires / plusieurs biens | Plusieurs biens **tranché** (EPIC-13) ; co-propriétaires **ici Q4** (et EPIC-11 Q10) |
| Q13 | Vues et favoris V12b / V15 | EPIC-09 / EPIC-10 (masqués tant que l’app acquéreur n’existe pas) |
| Q14 | « Chiffrement de bout en bout » | Plan EPIC-11 (Q5) |
| Q15 | Vendeur aussi acquéreur | Plan EPIC-11 (Q11) |
| Q16 | Sécurité du compte / e-mail | E-mail **lecture seule (tranché)** ; reste : plan EPIC-11 (Q6) |
| Q17 | Suppression de compte | Plan EPIC-11 (Q8) |
| Q18 | Résiliation du mandat | **Ici Q15** |

**Bloquantes pour coder EPIC-08 : Q2, Q3, Q12** (modèle de données). Toutes les autres ont un défaut réversible.

---

## Journal d’exécution

- 2026-10-03 : plan rédigé (aucun code), EPIC-08 créé (📋), README mis à jour.
- 2026-10-03 · O1 : migration `20261003080551_mise_en_vente.sql` (tables `sales`, `mandates`, `mandate_signatures`, `sale_requests`, `listing_photos` ; buckets `listing-media`, `mandate-signatures`, `sale-documents` ; RPC `choose_formula`, `sign_test_mandate`, `request_sale_service`, `cancel_sale_request`, `publish_listing`, `unpublish_listing`, `withdraw_sale`, `reorder_listing_photos`, `has_active_sale` pour EPIC-11 ; `staff_*` ; `notifications.kind` en contrôle de format, même instruction qu’EPIC-11), essai en transaction annulée + sonde RLS / RPC (propriétaire, autre vendeur, `anon`, lot « ensemble » / « ensemble ou séparément », signature, publication, Storage), poussée. La migration d’EPIC-11 (`20261003080523_coffre_fort_compte.sql`, déjà poussée) a été copiée telle quelle. Runbook `docs/runbooks/suivre-une-vente.md`.
- 2026-10-03 · O2 : Edge Function `render-mandate` (`pdf-lib` MIT, polices standard WinAnsi, filigrane « SPÉCIMEN », SHA-256, rendu déterministe, idempotente), modèle versionné `_shared/mandate/template.ts` (`test-2026-10`), tests Deno, déployée.
- 2026-10-03 · O3 : `SaleRepository` (+ modèles `Sale`, `SaleFormula`, `Mandate`, `SaleRequest`, `ListingPhoto`, `SaleFailure`) dans `packages/sale_repository`, 100 % ; `App` le reçoit seulement si `SALES_ENABLED` (config `development`).
- 2026-10-03 · O0 : `SignaturePad` (gagne l’arène des gestes au premier contact : pas de défilement en signant), `OfferPlanCard`, `PriceRangeSlider`, `RealestySwitch` / `SwitchRow` (+ galerie). `PlanTabs` = `RealestySegmentedControl` ; la chronologie V11c réutilise `SubmittedTimeline` (pas de promotion dans `lib/ui`).
- 2026-10-03 · O4–O9 : `lib/seller_space/sale/` (routes `/vendeur/ventes/<id>`, `…/annonce`, `…/annonce/photos`, `…/annonce/apercu` ; `SalesScope` dans `SellerTunnelShell` : `SalesCubit` + registre `SaleCubits`), V10, carte « Ma vente » (V9, fiche du lot), statut dans « Mes biens », V11 / V11b / V11c, feuille de signature, V11a, photos d’annonce (écran de prise de vue d’EPIC-15 rendu réutilisable via `PhotoCaptureTarget`), aperçu, retrait.
- 2026-10-03 · O10 : types de notifications EPIC-08 dans `AppNotificationKind`, parcours V9 → V10 → V11 → « Ma vente » dans `test/app/view/app_test.dart`, docs.
- 2026-10-03 · revue + arbitrages du porteur de projet : migration `20261003093204_mise_en_vente_ajustements.sql` (sonde annulée, dry-run, poussée ; `20261003081101_account_purge_fallback.sql` d’EPIC-11, déjà poussée, copiée telle quelle) — prix des services centralisés (`sale_service_price` / `SalePrices` : Premium 299 € + 99 €/mois, photographe 200 €, photo + vidéo 350 €, diagnostics « sur devis ») ; prix de présentation borné côté serveur à [50 % de la borne basse, 200 % de la borne haute] certifiées (trigger + contrôle à la signature ; l’app affiche « Hors fourchette » dans [×0,5 ; ×2] et bloque au-delà) ; mandat « sans engagement » résiliable après 30 jours minimum (`mandates.minimum_days`, `withdraw_sale` refuse avant, `staff_withdraw_sale` pour l’équipe) ; signature par nom tapé (`typed_test`, accessibilité) rendue dans le PDF ; `request_sale_service` refuse les créneaux passés et le rappel Premium hors Premium ; `listing_photos` contrôlé contre la cible de la vente. Modèle du mandat refondu sur la structure articles 1 à 15 du mandat exclusif Realesty (clauses génériques, **aucune donnée du mandat source**, variables du dossier, coordonnées Realesty SARL, honoraires TTC / HT, filigrane « SPÉCIMEN »), version `test-2026-10-b`, `render-mandate` redéployée. App : badges sans débordement (texte ×1,3 testé), onglets V10 « 1 % / Premium / 3 % », étapes « 1 · Mandat / 2 · Photos / 3 · Diagnostics » sur V11, exemples de bonnes photos (5 photos du porteur compressées sans métadonnées dans `assets/sale_examples/`, conseils de cadrage ; jeu de test IA brut dans `local_test_sets/`, ignoré par git), honoraires TTC + HT, identité du seul signataire sur V11c, ordre des biens d’un lot aligné sur la base (date puis id), copie de photo idempotente (la copie déjà faite gagne, fichier orphelin supprimé), aperçu sans promesse d’adresse.
- `has_active_sale(owner)` est laissée telle quelle : elle convergera avec `account_has_active_sale` d’EPIC-11 après sa fusion (EPIC-08 fusionne avant EPIC-11).

## Choix par défaut en attendant le porteur de projet

- **Durée (à confirmer)** : interprétation la plus simple de « sans engagement, résiliable à tout moment après 30 jours minimum » — appliquée à **toutes** les formules (y compris L’Expert, qui n’a plus de durée de 3 mois) ; avant 30 jours le retrait est refusé dans l’app (message avec la date), l’équipe peut toujours retirer une vente de test.
- **Bornes de prix** : [50 % de la somme des bornes basses certifiées ; 200 % de la somme des bornes hautes] ; sans avis de valeur, pas de borne.

Questions non bloquantes du §10, codées avec l’option recommandée (réversibles) :

- **Q1 accès** : drapeau `SALES_ENABLED` (seulement `config/development.json`) + `is_test` sur chaque vente et mandat ; sans drapeau, V9 garde « bientôt ».
- **Q2 (arbitrée) précision** : pour un lot « ensemble ou séparément », vente du lot **ou** des biens un par un, **jamais en même temps** (un bien en vente seul bloque la vente du lot et inversement) ; un lot « ensemble » ne se vend qu’en entier.
- **Q3 (arbitrée) précision** : « bien principal » = `property_lots.main_property_id`, à défaut le bien le plus ancien du lot ; le prix pré-rempli d’un lot = somme des valeurs certifiées de ses biens certifiés.
- **Q4 co-propriétaires** : le titulaire du compte signe (le propriétaire lié à son profil, sinon le n° 1) ; les autres « signeront hors de l’application », l’équipe enregistre leur signature.
- **Q5 identité** : pièce d’identité exigée pour toutes les formules ; vérification par l’équipe pour L’Expert seulement.
- **Q6 PDF** : serveur (`render-mandate`), texte de test court rédigé par nous, explicitement non contractuel.
- **Q7 Premium** : V11b → V11a (créneaux de visite avec EPIC-09).
- **Q8 V10** : onglet Premium par défaut ; « Comparer les 3 formules » masqué.
- **Q9 IA** : libellés neutres (« Présélection d’après votre audit », « Généré automatiquement ») ; retouche et home staging = préférences « Bientôt ».
- **Q10 description** : modèle déterministe en Dart, modifiable, régénérable.
- **Q11 publication / créneaux** : 5 photos minimum, la première est la couverture ; créneaux de shooting = 3 jours ouvrés suivants à 10 h / 14 h, jusqu’à 3 souhaités, confirmés par l’équipe.
- **Q12 (arbitrée) précision** : copie dans `listing-media` à la première ouverture des photos (puis « Reprendre les photos de mon dossier ») ; copie Storage inter-bucket faite par l’app.
- **Q13 adresse** : commune seulement dans l’aperçu.
- **Q14 tarifs** (arbitré) : 299 € + 99 €/mois (Premium), 200 € (photographe), 350 € (photo + vidéo), diagnostics « sur devis » ; affichés « indicatifs, rien n’est prélevé ».
- **Q15 retrait** : carte « Ma vente » (V9 et fiche du lot) ; « Ma formule » dans Compte avec EPIC-11 ; L’Expert peut se retirer à tout moment pendant les tests.
- **Q16** : changer de formule après signature = retirer (après 30 jours) puis recommencer.
- **Q17** : l’équipe joue l’agent (« Un agent vous contacte sous 24 h »).
- **Q18** : tout bien (ou lot) certifié, quel que soit le type (garage / terrain : seul l’ERP est présélectionné).

## Arbitrages du porteur de projet (2026-10-03) — prévalent sur le reste du plan
- Q2 : un lot se vend **en entier ou bien par bien** (les deux dès la v1).
- Q3 : un lot peut être mis en vente dès que son **bien principal** est certifié.
- Q12 : l'annonce reprend **toutes les photos du dossier, y compris celles où une personne est visible**.
- La promesse « visite 360° / vidéo immersive IA » (V10, V11) est **retirée jusqu'à la v3** ; on n'affiche que les photos.
- Rappels : signature de test uniquement, aucun paiement en v1.
