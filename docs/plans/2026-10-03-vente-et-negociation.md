# EPIC-10 · Commercialisation, négociation & suivi de la vente (V12b, V15, V16, V17) — plan d’implémentation

> Date : 2026-10-03. Statut : **plan (aucun code écrit)**.
> Sources lues : `CLAUDE.md`, `docs/decisions.md`, `docs/epics/*.md`, [spec V8b → V19](2026-10-01-parcours-vendeur-v8b-v19.md) (§1.3–1.4, §3 V12b / V15 / V16 / V17, §4.5, §4.6, §5.2–5.8, §6 EPIC-09 / EPIC-10, §7 Q8, Q13, Q18, §8), [plan EPIC-08](2026-10-03-offres-et-mise-en-vente.md) (y compris « Arbitrages du porteur de projet »), migration d’EPIC-08 `20261003080551_mise_en_vente.sql` + `packages/sale_repository` (branche `feat/epic-08-formules-mise-en-vente`), migration et plan d’EPIC-11 (branche `feat/epic-11-coffre-fort-compte` : `account_has_active_sale` attend déjà `under_offer` / `under_compromis`, `pg_cron`, coffre-fort « Mandats & visites »), [plan EPIC-12](2026-10-03-back-office-expert.md), maquettes `PerformanceVente`, `Commercialisation`, `Negociation`, `SuiviVente`, `CompteRendu` (`scratchpad/seller-design-next/project/*.dc.html`).
> Plan frère (même date) : [Visites](2026-10-03-visites.md) (EPIC-09 : V12, V13, V13b, V14).

---

## 0. Contexte et périmètre

Avec EPIC-08, une vente (`sales`, un bien **ou** un lot) passe par `plan_chosen` → `mandate_signed` → `published` (ou `withdrawn`). Avec EPIC-09, le vendeur ouvre ses créneaux et traite des demandes de visite. Il manque tout ce qui suit la publication : **suivre l’activité de l’annonce**, **recevoir et négocier des offres**, puis **suivre la vente jusqu’à l’acte** chez le notaire. Il n’existe **ni app acquéreur, ni Espace Agences, ni notaire connecté**.

**Dans le périmètre d’EPIC-10** :
- V12b : **tableau de bord de vente** (formules 1 %) : demandes, visites, offres, diffusion, retours des visiteurs ;
- V15 : **commercialisation L’Expert (3 %)** : agent, compteurs, offre à examiner, fil d’activité ;
- V16 : **négociation** : offre reçue, accepter / refuser / **contre-proposer**, historique ; liste des offres d’une vente ;
- V17 : **suivi de la vente** : offre acceptée → compromis → rétractation → condition de prêt → acte authentique ; copie du compromis ; interlocuteurs (notaire, agent L’Expert) ;
- nouvelles étapes de vente `under_offer`, `under_compromis`, `sold` ; `sale_contacts`, `sale_milestones`, `sale_documents`, `offers` ; vue `sale_events` ;
- notifications in-app ; fonctions `staff_*` + runbook pour **saisir les offres, les réponses des acquéreurs, les jalons et les documents** à leur place.

**Hors périmètre** : app acquéreur (A1+), Espace Agences (P1+), accès du notaire, paiements et factures (aucun en v1), signature électronique, messagerie in-app, diffusion sur les portails et leurs statistiques, partenaires « Préparer le déménagement » (C3), bouton « Une question ? ».

### 0.1 Ce qui fonctionne en v1 sans acquéreurs

| Fonction | En v1 | Plus tard |
|---|---|---|
| V12b / V15 compteurs | **Réels** pour demandes, visites, offres (tables Realesty) ; **vues et favoris masqués** (Q2) | Vues / favoris de l’app acquéreur, puis des portails |
| Offres reçues | **Saisies par l’équipe** (`staff_record_offer`, `source = staff` ou `agency`) : offre transmise par téléphone, par l’agent L’Expert ou une agence ; **démo** `source = demo` | `make_offer` depuis l’app acquéreur (`buyer_user_id`) |
| Réponse du vendeur (accepter / refuser / contre-proposer) | **Réelle** (RPC) ; l’équipe transmet à l’acquéreur | L’acquéreur la reçoit dans son app |
| Réponse de l’acquéreur à une contre-proposition | **Saisie par l’équipe** (`staff_record_buyer_response`) | `respond_counter_offer` (acquéreur) |
| Jalons, compromis, acte, interlocuteurs | **Saisis par l’équipe** à partir des informations du notaire / de l’agent | Espace Agences, notaire (lecture) |
| Commission | **Affichée** (taux × prix), rien n’est facturé ni prélevé | Facturation (EPIC paiements) |

Tout ce qui est saisi pendant la phase de test porte **`is_test = true`** ; V16 et V17 affichent alors un bandeau « Phase de test : offre fictive, sans valeur juridique ».

## 1. Décisions déjà prises (rappel, à ne pas rediscuter)

| Décision | Source | Conséquence ici |
|---|---|---|
| **Aucun paiement en v1** ; **mandat de test seulement**, montage juridique à valider avant tout vrai vendeur | `decisions.md` 2026-10-01, EPIC-08 | Commission affichée à titre indicatif ; offres et acceptations sont des **données de test** (`is_test`) tant que le montage n’est pas validé. |
| **Notifications dans l’app uniquement** (pas de SMS / e-mail avant Brevo, pas de push) | `decisions.md` 2026-10-01 | Offre reçue, contre-proposition, acceptation, jalons → `notifications`. L’équipe prévient acquéreur et notaire hors app. |
| **Un lot se vend en entier ou bien par bien** (jamais les deux à la fois) ; mise en vente dès que le bien principal est certifié | `decisions.md` 2026-10-03, EPIC-08 | Une offre porte sur **une vente** (le lot entier, ou un bien) ; pas d’offre partielle (Q11). |
| **Plusieurs biens par vendeur** (≤ 5) | EPIC-13 | Chaque vente a son tableau de bord, ses offres et son suivi ; V9 / « Mes biens » montrent l’étape de chaque vente. |
| **Suppression de compte = désactivation puis suppression sous 30 jours**, refusée avec une vente active | `decisions.md` 2026-10-03, EPIC-11 | `account_has_active_sale` (EPIC-11) compte déjà `under_offer` et `under_compromis` ; `has_active_sale` d’EPIC-08 est recréée de même. |
| **RLS partout**, transitions par RPC `security definer`, `staff_*` en `security invoker` retirées aux rôles client | `CLAUDE.md`, EPIC-07 / EPIC-12 | Même schéma ; EPIC-12 ajoutera les `bo_*` (rôle `agent` plus tard). |
| IA via OpenRouter seulement ; l’IA n’invente aucun chiffre | `CLAUDE.md` | **Aucune IA** : les bulles de l’agent (« Cette offre est 3,8 % sous votre prix… ») sont des modèles calculés dans l’app. |
| Ventes réservées à la saveur `development` (`SALES_ENABLED`) | EPIC-08 | Même drapeau pour V12b, V15, V16, V17. |
| V12b dans EPIC-09 selon la spec §6 | spec | **Déplacé dans EPIC-10** : V12b affiche surtout des offres et des statistiques de commercialisation, et dépend des tables de cet epic. |

## 2. Modèle de données — migration `AAAAMMJJhhmmss_vente_et_negociation.sql`

Additive, `text + check`, triggers `seller_tunnel_set_updated_at`, RLS propriétaire seul, aucune écriture directe des colonnes d’état. Prérequis : migrations d’EPIC-08, d’EPIC-11 et d’EPIC-09 (`visit_requests`) poussées.

### 2.1 `sales` (extension) et étapes de vente

- `stage` : contrôle remplacé (`drop constraint if exists` + `add constraint`) par (`plan_chosen`, `mandate_signed`, `published`, **`under_offer`**, **`under_compromis`**, **`sold`**, `withdrawn`) — mêmes noms que ceux attendus par EPIC-11.
- Nouvelles colonnes (aucun grant d’écriture) : `accepted_offer_id` uuid null → `offers` (deferrable), `offer_accepted_at`, `compromis_signed_at`, `sold_at` timestamptz, `final_price_eur` int null, `deal_cancelled_at` timestamptz, `deal_cancel_reason` text ≤ 300.
- Fonctions d’EPIC-08 / EPIC-09 recréées :
  - `has_active_sale` : + `under_offer`, `under_compromis` ;
  - `withdraw_sale` : refusée à partir de `under_offer` (`sale_under_offer` → « Contactez votre conseiller ») (Q10) ;
  - `visit_sale_accepts_requests` (EPIC-09) : `published` **et** `under_offer` (Q9).
- Les politiques d’EPIC-08 (édition de l’annonce et des photos si `stage in ('plan_chosen', 'mandate_signed', 'published')`) restent inchangées : **l’annonce est figée** dès qu’une offre est acceptée.
- L’index `sales_one_active_per_property` (`stage <> 'withdrawn'`) garde une vente `sold` : un bien vendu ne peut pas être remis en vente (Q19).

Transitions :

```
published ──(offre acceptée)──► under_offer ──(compromis signé)──► under_compromis ──(acte signé)──► sold
     ▲                               │                                   │
     └──────── staff_cancel_deal (rétractation, refus de prêt, désistement) ┘
```

### 2.2 `offers` — offres et contre-propositions (prêtes pour l’app acquéreur)

| Colonne | Type / règle |
|---|---|
| `id` | uuid pk (choisi par l’appelant : rejouable) |
| `sale_id` | uuid not null → `sales` on delete cascade |
| `owner_id` | uuid not null (vendeur, dénormalisé) |
| `root_offer_id` | uuid null → `offers` (première offre de l’acquéreur : un fil de négociation ; null pour elle-même) |
| `parent_offer_id` | uuid null → `offers` (l’offre à laquelle celle-ci répond) |
| `round` | smallint not null default 1 |
| `from_party` | text not null check in (`buyer`, `seller`) |
| `buyer_user_id` | uuid null → `auth.users` on delete set null (app acquéreur plus tard) |
| `buyer_label`, `buyer_initials` | comme `visit_requests` (prénom + initiale) |
| `buyer_snapshot` | jsonb, même contrôle que les visites (`visit_buyer_snapshot_is_valid`) + clé `pass_visite` |
| `visit_request_id` | uuid null → `visit_requests` on delete set null (visite + compte rendu liés) |
| `amount_eur` | int not null check 1 000 – 100 000 000 |
| `financing` | text check in (`loan`, `cash`, `mixed`, `unknown`) |
| `financing_status` | text check in (`broker_agreement`, `bank_agreement`, `simulation`, `unknown`) → « Prêt · accord courtier » |
| `suspensive_conditions` | text[] ⊂ (`loan`, `sale_of_property`, `building_permit`, `other`) ; `conditions_note` ≤ 200 |
| `desired_signing_before` | date null |
| `valid_until` | timestamptz not null (défaut : création + 7 jours, Q6) |
| `message` | text ≤ 500 (message de l’acquéreur, ou du vendeur pour une contre-proposition) |
| `status` | text not null default `pending` check in (`pending`, `accepted`, `refused`, `countered`, `expired`, `withdrawn`, `cancelled`) |
| `status_reason` | text null check in (`other_offer_accepted`, `price_too_low`, `conditions`, `other`, `deal_cancelled`) |
| `response_message` | text ≤ 500 (réponse du vendeur à transmettre, facultative) |
| `agent_advice` | text ≤ 500 (L’Expert : conseil de l’agent, écrit par l’équipe) |
| `allocation` | jsonb null (lot vendu en entier : ventilation par bien saisie par l’équipe au compromis, Q11) |
| `source` | text not null check in (`buyer_app`, `staff`, `agency`, `demo`) |
| `is_test` | boolean not null default true |
| `created_at`, `responded_at`, `expiry_notified_at`, `updated_at` | |

Index et invariants :
- `unique (sale_id) where status = 'accepted'` : une seule offre acceptée par vente ;
- `unique (root_offer_id) where status = 'pending' and root_offer_id is not null` + même règle pour la racine : **une seule proposition en attente par fil** ;
- trigger `offers_check` : vente du bon propriétaire ; à la création d’une offre d’acquéreur, vente en `published` (ou `under_offer` si offres de secours, Q4 b) ; contre-proposition = `from_party` opposé au parent ; propriétaire non désactivé.
- RLS : `select` du vendeur (`owner_id = auth.uid()`) ; aucune écriture directe. Plus tard, l’acquéreur lira ses offres par une fonction `my_offers()` (sans `agent_advice`, sans `status_reason` interne).

### 2.3 `sale_milestones` — étapes jusqu’à l’acte

`id`, `sale_id`, `owner_id`, `kind` check in (`offer_accepted`, `compromis_signed`, `retraction_end`, `loan_condition`, `other_condition`, `deed_signed`), `position` smallint, `due_date` date null, `due_label` text ≤ 40 (« mi-janvier »), `status` check in (`todo`, `done`, `failed`, `waived`), `done_at`, `note` ≤ 300, `document_id` null → `sale_documents`, `created_at`, `updated_at`. `unique (sale_id, kind) where kind <> 'other_condition'`.
- Créés à l’acceptation : `offer_accepted` (fait), `compromis_signed`, `retraction_end`, `loan_condition` (si l’offre l’a), `deed_signed` (à faire).
- `retraction_end` : **date saisie par l’équipe** ; à défaut, pré-calcul indicatif signature + 10 jours avec la mention « date indicative, confirmée par le notaire » (le délai légal court à partir du lendemain de la notification, Q14).
- RLS : `select` vendeur ; écriture équipe.

### 2.4 `sale_contacts` — interlocuteurs

`id`, `sale_id`, `owner_id`, `role` check in (`agent`, `notary`, `other`), `name` ≤ 100, `organisation` ≤ 120, `area_label` ≤ 80 (« Ouest lyonnais »), `address` ≤ 200, `phone` ≤ 30, `email` ≤ 120, `response_time_label` ≤ 60 (« répond sous 24 h »), `initials` ≤ 3, `position`, `created_at`, `updated_at`. RLS : `select` vendeur ; écriture équipe (Q12, Q13). Le contact `agent` d’une vente L’Expert remplace « Un agent vous contacte sous 24 h » d’EPIC-08 (notification `sale_contact_assigned`).

### 2.5 `sale_documents` — documents de la vente

`id`, `sale_id`, `owner_id`, `kind` check in (`compromis`, `acte`, `offre`, `avenant`, `autre`), `title` ≤ 120, `storage_path` (bucket **`sale-documents`** d’EPIC-08, `<owner id>/<sale id>/…`, lecture propriétaire déjà en place), `pages` smallint, `size_bytes`, `sha256`, `created_at`. Écrit par `staff_attach_sale_document` (contrôle du chemin et de l’existence de l’objet, comme `staff_attach_valuation_report`). Le coffre-fort d’EPIC-11 les montre en lignes virtuelles dans « Mandats & visites », avec les offres (Q15).

### 2.6 Vue `sale_events` (`security_invoker = true`)

Union datée pour le fil « Activité » de V15 et l’historique de V16 : mandat signé, annonce publiée, visites acceptées / réalisées (EPIC-09), comptes rendus publiés, offres reçues / contre-propositions / réponses, jalons faits. Colonnes : `sale_id`, `at`, `kind`, `label_params jsonb`, `target_type`, `target_id`. Les libellés sont construits dans l’app (l10n).

### 2.7 RPC du vendeur (`security definer`, `authenticated`)

| Fonction | Contrôles | Effet |
|---|---|---|
| `respond_offer(p_offer_id uuid, p_decision text, p_reason text default null, p_message text default null)` | offre d’acquéreur du vendeur, `pending`, non expirée ; vente `published` | `accepted` : vente `under_offer`, `accepted_offer_id`, autres offres en attente `refused` (`other_offer_accepted`, Q4), jalons créés, notification ; `refused` : motif + message facultatifs. Rejouable |
| `counter_offer(p_offer_id uuid, p_counter_id uuid, p_amount int, p_message text default null)` | parent = offre d’acquéreur `pending`, non expirée ; `offre < montant ≤ prix affiché` (Q5) ; message ≤ 500 | parent `countered` ; nouvelle offre `from_party = seller`, `pending`, `valid_until` + 7 jours ; rejouable avec le même `p_counter_id` |
| `withdraw_counter_offer(p_counter_id uuid)` | contre-proposition du vendeur `pending` | `withdrawn` ; le fil n’a plus de proposition en attente (l’équipe en informe l’acquéreur) |
| `sale_dashboard(p_sale_id uuid, p_since timestamptz default null) returns jsonb` | vente du vendeur | compteurs (demandes, visites réalisées, à venir, offres reçues, à examiner), dernière offre, points appréciés / freins les plus cités (comptes rendus), en ligne depuis ; `views` et `favorites` à null (app acquéreur plus tard) |

Erreurs typées : `offer_not_pending`, `offer_expired`, `counter_out_of_range`, `sale_not_published`, `sale_under_offer`, mappées en l10n.

### 2.8 Notifications

Types EPIC-10 : `offer_received`, `offer_countered` (l’acquéreur relance), `offer_accepted_by_buyer` (il accepte la contre-proposition), `offer_withdrawn`, `offer_expired`, `sale_contact_assigned`, `sale_milestone` (jalon fait ou date mise à jour), `deal_cancelled`, `sale_completed`. Routes : `/vendeur/ventes/<sale>/offres/<offer>`, `/vendeur/ventes/<sale>/suivi`.

### 2.9 Fonctions équipe (`security invoker`, retirées à `public`, `anon`, `authenticated`)

| Fonction | Usage |
|---|---|
| `staff_record_offer(p_sale_id, p_amount, p_buyer_label, p_buyer_initials, p_financing, p_financing_status, p_conditions text[], p_desired_signing_before, p_valid_days default 7, p_message, p_visit_request_id default null, p_source default 'staff', p_snapshot jsonb default '{}', p_offer_id uuid default gen_random_uuid()) returns uuid` | offre transmise par un acquéreur ou une agence ; notification `offer_received` |
| `staff_record_buyer_response(p_offer_id, p_decision, p_amount default null, p_message default null)` | réponse de l’acquéreur à une contre-proposition : `accepted` (→ `under_offer`), `refused`, `countered` (nouvelle offre d’acquéreur dans le fil) |
| `staff_withdraw_offer(p_offer_id, p_reason)` | l’acquéreur retire son offre |
| `staff_set_agent_advice(p_offer_id, p_advice)` | L’Expert : conseil de l’agent affiché dans V16 |
| `staff_upsert_sale_contact(...)` / `staff_remove_sale_contact(p_id)` | agent, notaire |
| `staff_set_milestone(p_sale_id, p_kind, p_status, p_due_date, p_due_label, p_note)` | dates et avancement ; notification `sale_milestone` |
| `staff_attach_sale_document(p_sale_id, p_kind, p_path, p_pages, p_title)` | compromis, acte… déposés dans `sale-documents` |
| `staff_record_compromis(p_sale_id, p_signed_on, p_retraction_end default null, p_loan_deadline default null, p_document_id default null)` | `under_compromis` ; demandes de visite en attente refusées (`sale_closed`), visites futures annulées (`cancelled_by = system`) ; annonce hors ligne |
| `staff_cancel_deal(p_sale_id, p_reason)` | rétractation, refus de prêt, désistement : offre acceptée `cancelled`, jalons `failed`, vente de nouveau `published`, notification `deal_cancelled` (Q20) |
| `staff_record_deed(p_sale_id, p_signed_on, p_final_price)` | `sold`, `sold_at`, `final_price_eur`, jalon fait, notification `sale_completed` |
| `staff_seed_demo_offer(p_sale_id)` / `staff_purge_demo_offers(p_sale_id)` | offre de la maquette (Thomas & Léa B., 505 000 €… adaptée au prix affiché) liée à une visite de démo, `source = demo` |

Runbook : **`docs/runbooks/suivre-une-vente.md`** (EPIC-08) complété par N1 : §6 Offres, §7 Interlocuteurs, §8 Compromis et jalons, §9 Acte et annulation, §10 Démo.

### 2.10 Tâche `pg_cron` horaire `offers-housekeeping`

`offers_housekeeping()` : offres et contre-propositions `pending` dont `valid_until` est passé → `expired` + notification `offer_expired` (une fois). Lançable à la main ; l’app affiche « Expirée » si la date est passée même si la tâche a du retard.

### 2.11 Sonde RLS (bloc `DO` annulé)

Vendeur : voit ses offres, jalons, contacts, documents, événements ✔ ; ceux d’un autre ✘ ; `update` direct de `offers.status` ou `sales.stage` ✘ ; accepter une offre expirée ✘, déjà refusée ✘, d’une vente retirée ✘ ; deux acceptations ✘ (index) ; contre-proposition sous l’offre ✘ ou au-dessus du prix affiché ✘ ; deuxième contre-proposition en attente ✘ ; `withdraw_sale` en `under_offer` ✘ ; écriture dans `sale-documents` ✘ ; `staff_*` refusées à `authenticated` ✘ ; `has_active_sale` / `account_deletion_blockers` vrais en `under_compromis` ✔ ; `anon` ne voit rien.

### 2.12 Ce que l’app acquéreur branchera plus tard (aucun code en v1)

`make_offer` (acquéreur Pass Visite, visite réalisée selon une règle à décider avec A-écrans), `respond_counter_offer`, `withdraw_my_offer`, `my_offers()` (colonnes limitées) ; accès du notaire en lecture aux documents marqués « Notaire » (visibilité d’EPIC-11) ; vues et favoris (`listing_views`, `listing_favorites`) lus par `sale_dashboard` ; rôle `agent` (EPIC-12 / P-écrans) limité aux ventes déléguées pour saisir offres, conseils et jalons via des `bo_*`.

## 3. Fonctions serveur

- **Aucune Edge Function obligatoire**, aucun appel IA.
- Facultatif (Q15 b) : `render-offer` (même modèle que `render-mandate` : PDF filigrané « SPÉCIMEN », SHA-256, `sale-documents`). **Non prévue en v1** si Q15 = (a).
- Tâche `pg_cron` §2.10.

## 4. Écrans et parcours

Routes : enfants de la vente d’EPIC-08 (`/vendeur/ventes/<saleId>`, plein écran au-dessus des onglets, Q17) ; `SaleRouteScope` d’EPIC-08 étend son aiguillage.

| Écran | Route | Entrée autorisée | Maquette |
|---|---|---|---|
| V12b Tableau de bord de vente | `/vendeur/ventes/<saleId>/tableau-de-bord` | formule 1 %, `stage` ≥ `published` | `PerformanceVente.dc.html` |
| V15 Commercialisation | `/vendeur/ventes/<saleId>/commercialisation` | L’Expert, `stage` ≥ `mandate_signed` | `Commercialisation.dc.html` |
| Offres de la vente | `/vendeur/ventes/<saleId>/offres` | au moins une offre | **absent du canevas** |
| V16 Négociation | `/vendeur/ventes/<saleId>/offres/<offerId>` | offre de la vente | `Negociation.dc.html` |
| V17 Suivi de la vente | `/vendeur/ventes/<saleId>/suivi` | `under_offer`, `under_compromis`, `sold` | `SuiviVente.dc.html` |

Aiguillage de `/vendeur/ventes/<id>` : 1 % publiée → V12b ; L’Expert signée → V15 ; `under_offer` et après → V17. Carte « Ma vente » (V9, fiche du lot) : libellés « Sous offre », « Sous compromis », « Vendu le … », accent « 1 offre à examiner » → V16 ; « Mes biens » : statut de même.

### 4.1 V12b · Tableau de bord de vente (`SalesBoardPage`)
- Badges formule + « En ligne depuis 12 jours » ; `AgentBubble` calculée (sans vues en v1) : « {visites} visites ont eu lieu. Une offre vous attend : ouvrez-la pour y répondre. » ; segments « 7 jours » · « 30 jours » · « Depuis la mise en ligne ».
- `KpiTile` × 4 : « Demandes de visite », « Visites réalisées », « Visites à venir », « Offres reçues » (« Vues de l’annonce » et « Mises en favori » masquées, Q2).
- « Offres » + « 1 à examiner » → lignes d’offre (initiales, nom, « Reçue aujourd’hui · financement validé », montant) → V16 ; « Prochaines visites » + « Tout voir » → V13 (EPIC-09) ; « Diffusion de l’annonce » : ligne « Realesty · En ligne » seulement (Q3) ; « Retours des visiteurs » : puces des points appréciés / freins les plus cités → dernier compte rendu (V14).

### 4.2 V15 · Commercialisation L’Expert (`ExpertSalePage`)
- Titre « Ma vente » + cloche ; badges « L’Expert · 3 % » + étape (« En commercialisation », « Sous offre »…) ; titre « Votre vente est pilotée par nos agents ».
- Carte agent (`ContactCard` : initiales, nom, zone, délai de réponse, « Appeler » `tel:` / « Message » `mailto:` via `url_launcher`, déjà dépendance) ; sans contact : « Un agent vous contacte sous 24 h ».
- `KpiTile` × 3 : « Demandes de visite » (libellé « Pass Visite » quand l’app acquéreur existera), « Visites », « Offres » (« Vues » masquée) ; bandeau accent « 1 offre à examiner » → V16.
- « Activité » : `SubmittedTimeline` sur `sale_events` ; « Voir le dernier compte rendu » → V14.

### 4.3 V16 · Négociation (`NegotiationPage`) et liste des offres
- `AgentBubble` calculée : « Cette offre est {écart} % sous votre prix, avec un financement déjà validé. » (variantes : au prix, au-dessus, financement non validé) ; L’Expert : bloc « Conseil de votre agent » (`agent_advice`).
- Carte offre : initiales, nom, « Offre reçue aujourd’hui · valable 7 jours », badge « Pass Visite » ; montant + « −3,8 % vs prix affiché » ; `KeyValueRow` « Prix affiché », « Financement », « Condition suspensive », « Signature souhaitée ».
- « Refuser » → feuille (motif, message facultatif) ; « Accepter » → feuille intégrée « Accepter l’offre de 505 000 € ? Les autres offres en attente seront refusées. » + « Votre conseiller Realesty prévient l’acquéreur et le notaire pour préparer le compromis. » (Q8) → V17.
- « Faire une contre-proposition » : champ « Montant proposé » + `PriceRangeSlider` borné (offre exclue → prix affiché), « Message » (500 caractères, exemple de la maquette en indication), CTA collant « Envoyer la contre-proposition » (motif du tunnel : toujours actif, erreurs affichées, délai 15 s).
- « Historique » : fil de l’offre (offres / contre-propositions, dates) + visite et compte rendu liés ; mention « Chaque offre est horodatée et archivée dans votre coffre-fort. ».
- États : contre-proposition en attente (« En attente de la réponse de l’acquéreur · jusqu’au … » + « Retirer ma contre-proposition ») ; offre refusée / expirée / retirée / acceptée en lecture seule ; bandeau test si `is_test`.
- Liste des offres (non dessinée) : « À examiner », « En cours », « Clôturées », une ligne par fil.

### 4.4 V17 · Suivi de la vente (`SaleTrackingPage`)
- Titre « Ma vente », badge d’étape, « Suivi de la vente », libellé du bien ou du lot ; `AgentBubble` depuis le prochain jalon (« Prochaine étape : {jalon}, avant le {date}. ») ; tuiles « Prix de vente » (offre acceptée puis prix de l’acte) et « Commission {taux} % » (montant via `SaleFormula.commissionOn`, mention « indicatif, rien n’est prélevé dans l’app », Q16).
- Jalons (`SubmittedTimeline`) : « Offre acceptée · 515 000 € », « Compromis signé · copie disponible », « Délai de rétractation » (« Terminé le … » une fois passé ; « date indicative » si pré-calculée), « Condition suspensive : prêt · Échéance le … », « Acte authentique · Prévu mi-janvier chez le notaire ».
- « Copie du compromis · PDF · 32 pages » + « Télécharger » (URL signée de `sale-documents`) si présent.
- « Vos interlocuteurs » : carte notaire (sinon « Votre notaire n’est pas encore renseigné : indiquez-le à votre conseiller Realesty ») ; carte agent seulement en L’Expert.
- « Préparer le déménagement » masqué (C3 hors périmètre). Vente `sold` : en-tête « Vendu le … », jalons faits.

## 5. Données côté app

- **`packages/sale_repository`** : `OfferRepository` (`listOffers(saleId)`, `getOffer`, `respond`, `counter`, `withdrawCounter`, `dashboard(saleId, since)`, `events(saleId)`) et `SaleTrackingRepository` (`milestones`, `contacts`, `documents`, `documentUrl`) ; modèles `Offer`, `OfferStatus`, `OfferParty`, `Financing`, `SuspensiveCondition`, `SaleDashboard`, `SaleEvent`, `SaleMilestone`, `SaleContact`, `SaleDocument` ; `SaleStage` + `underOffer`, `underCompromis`, `sold` ; `Sale` + champs §2.1 ; échecs typés `OfferFailure(code)`.
- `AppNotificationKind` : types §2.8.
- `lib/seller_space/sale/` : `board/` (V12b), `expert_sale/` (V15), `negotiation/` (V16 + liste + feuilles), `tracking/` (V17), `widgets/` (lignes d’offre, `ContactCard`, libellés d’étape) ; cubits par écran (Page / View) fournis sous `SaleRouteScope`.
- Design system : `KpiTile` (promu depuis V8b s’il y existe, sinon nouveau), `ContactCard` ; `SubmittedTimeline` et `PriceRangeSlider` réutilisés.
- l10n : préfixes `salesBoard*`, `expertSale*`, `negotiation*`, `offers*`, `saleTracking*`, `saleStage*`.
- Coffre-fort (EPIC-11) : `VaultCubit` ajoute les offres et `sale_documents` en lignes virtuelles « Mandats & visites » (tranche N8).

## 6. User stories (EPIC-10)

- **US-10.1 · Tableau de bord de vente (V12b)** — *En tant que vendeur 1 %, je veux suivre l’activité de mon annonce.* Période 7 j / 30 j / depuis la mise en ligne ; demandes, visites réalisées et à venir, offres ; vues et favoris masqués sans app acquéreur ; diffusion « Realesty » ; offre → V16, visites → V13, retours → V14.
- **US-10.2 · Ma vente avec L’Expert (V15)** — *En tant que vendeur 3 %, je veux voir mon agent, l’activité et les offres.* Carte agent (Appeler / Message) ou « Un agent vous contacte sous 24 h » ; compteurs ; bandeau d’offre ; fil d’activité daté ; dernier compte rendu.
- **US-10.3 · Recevoir une offre** — *En tant que vendeur, je veux être prévenu d’une offre et la lire en détail.* Notification ; montant, écart au prix affiché, financement, conditions, date souhaitée, validité ; conseil de l’agent en L’Expert ; visite et compte rendu liés.
- **US-10.4 · Accepter ou refuser une offre** — Acceptation avec confirmation intégrée ; les autres offres en attente sont refusées ; la vente passe « Sous offre » et l’annonce est figée ; refus avec motif et message facultatifs.
- **US-10.5 · Contre-proposer** — Montant borné entre l’offre et le prix affiché, message de 500 caractères ; une seule proposition en attente par fil ; retrait possible ; historique horodaté ; expiration après 7 jours.
- **US-10.6 · Suivre la vente jusqu’à l’acte (V17)** — Prix et commission indicative ; jalons offre, compromis, rétractation, prêt, acte ; copie du compromis ; notaire et agent (L’Expert) ; notification à chaque jalon ; état « Vendu ».
- **US-10.7 · Annulation d’une vente en cours** — Rétractation ou refus de prêt saisis par l’équipe : vente republiée, offre « annulée », notification ; pas de retrait par le vendeur après acceptation (« Contactez votre conseiller »).
- **US-10.8 · Retrouver mes offres et documents** — Liste des offres de la vente ; offres et documents de la vente dans le coffre-fort « Mandats & visites ».
- **US-10.9 · Saisie par l’équipe (avant l’app acquéreur et l’Espace Agences)** — `staff_*` et runbook « Suivre une vente » complété : offres, réponses de l’acquéreur, conseils, contacts, jalons, documents, compromis, acte, annulation ; démo marquée et supprimable.
- **US-10.10 · Prêt pour l’app acquéreur** — `buyer_user_id`, fils de négociation, `source`, instantané contrôlé, compteurs prévus pour vues / favoris ; aucune jointure vers les tables de l’acquéreur.

## 7. Découpage (tranches de 1 à 2 h, un agent codeur chacune)

| # | Tranche | Fichiers possédés | Dépend de |
|---|---|---|---|
| N0 | DS : `KpiTile`, `ContactCard` (+ galerie, tests) | `lib/ui/components/<nouveaux>.dart`, `lib/ui/ui.dart`, `lib/ui/gallery/**` | — |
| N1 | Migration `*_vente_et_negociation.sql` (§2), tâche `pg_cron`, essai annulé, sonde RLS, `db push` ; runbook `suivre-une-vente.md` §6–§10 | `supabase/migrations/*_vente_et_negociation.sql`, `docs/runbooks/suivre-une-vente.md` | EPIC-08, EPIC-11, **EPIC-09 VI1** poussés |
| N2 | `OfferRepository`, `SaleTrackingRepository`, modèles, `SaleStage` étendu, tests 100 % ; `App` / `bootstrap` / mocks | `packages/sale_repository/lib/src/{offers,tracking}/**`, `.../models/{sale,app_notification}.dart`, `lib/bootstrap.dart`, `lib/app/view/app.dart`, `test/helpers/mocks.dart` | N1 |
| N3 | Routes, aiguillage de `SaleRouteScope`, carte « Ma vente » et « Mes biens » (nouvelles étapes) | `lib/app/router/**`, `lib/seller_space/sale/{sale_routes,sale_route_scope}.dart`, `lib/seller_space/sale/widgets/{sale_card,sale_labels}.dart`, `lib/seller_space/my_properties/widgets/property_row.dart` | N2 |
| N4 | V16 + liste des offres + feuilles | `lib/seller_space/sale/negotiation/**`, ARB `negotiation*`, `offers*` | N0, N3 |
| N5 | V12b | `lib/seller_space/sale/board/**`, ARB `salesBoard*` | N0, N3 |
| N6 | V15 | `lib/seller_space/sale/expert_sale/**`, ARB `expertSale*` | N0, N3 |
| N7 | V17 | `lib/seller_space/sale/tracking/**`, ARB `saleTracking*` | N0, N3 |
| N8 | Raccords : V14 « Ouvrir la négociation » (EPIC-09), coffre-fort « Mandats & visites » (EPIC-11, si fusionné) | `lib/seller_space/visits/report/**` (bouton), `lib/seller_space/vault/**` (lignes virtuelles) | N4, EPIC-09, EPIC-11 |
| N9 | Intégration : parcours `app_test.dart` (V9 → V12b → V16 contre-proposition → acceptation → V17), `CLAUDE.md`, epic, journal ; contrôle iPhone avec la démo | `test/app/view/app_test.dart`, docs | toutes |

Vagues : **{N0, N1}** → **{N2}** → **{N3}** → **{N4, N7}** → **{N5, N6, N8}** → **{N9}**. Écritures ARB sérialisées ; chaque tranche vérifiée par un agent indépendant (tests, revue, rendu 390 px vs maquettes).

## 8. Tests et vérification

- **SQL** : essai en transaction annulée, sonde §2.11, scénarios complets avec les `staff_*` (offre → contre-proposition → réponse de l’acquéreur → acceptation → compromis → acte ; et annulation → retour `published`) ; `offers_housekeeping()` à la main.
- **Paquet** : repositories et modèles à 100 %, mapping des codes d’erreur, analyse de `sale_dashboard` et `sale_events`.
- **App** : `blocTest` (acceptation, contre-proposition hors bornes, délai de 15 s, rejouabilité) ; widgets 390 × 844 pour V12b, V15 (avec / sans agent), V16 (chaque état), V17 (chaque étape, `sold`) ; calculs d’écart et de commission testés ; parcours `app_test.dart`.
- **Manuel (iPhone, `development`)** : vente de test publiée, `staff_seed_demo_offer`, contre-proposition, réponse saisie par l’équipe, acceptation, jalons et compromis, acte, purge.
- CI : analyse, format, bloc lint, couverture 100 %.

## 9. Risques

| Risque | Parade |
|---|---|
| Portée juridique : en France, l’accord sur la chose et le prix peut valoir vente ; un texte « l’acceptation n’engage pas » serait faux | Phase de test uniquement (`is_test`, bandeau) ; texte neutre (« votre conseiller prévient le notaire ») ; validation par un juriste avant tout vrai vendeur, comme le mandat (Q8). |
| Données saisies à la main (montants, dates, identité de l’acquéreur) | Contrôles SQL (bornes, listes, longueurs) ; runbook avec modèles ; prénom + initiale seulement. |
| Délai de rétractation mal calculé | Date saisie par l’équipe ; pré-calcul marqué « indicatif » (Q14). |
| Machine à états complexe (offres concurrentes, expiration, annulation) | Index uniques partiels, verrous de ligne dans les RPC, sonde de chaque transition, tests de bout en bout en SQL. |
| Modifications de fonctions d’EPIC-08 / EPIC-09 (`withdraw_sale`, `has_active_sale`, `visit_sale_accepts_requests`) | `create or replace` dans la migration d’EPIC-10, après fusion des deux ; sonde de non-régression d’EPIC-08. |
| Conflits de fichiers (carte « Ma vente », routes, V14, coffre-fort) | N3 et N8 isolés, après fusion d’EPIC-08 / 09 / 11 ; liens par `isRouteAvailable`. |
| Écrans attendus avec barre d’onglets (maquettes) mais routes de vente plein écran | Q17 ; écart signalé. |

## 10. Écarts de maquette à signaler à Claude Design

V12b : badge Premium figé, tuiles vues / favoris et portails sans données, « Agences partenaires » ; V15 : « 1 248 Vues », « Message » sans messagerie ; V16 : retour vers V15 même pour un vendeur 1 %, pas de feuille de confirmation d’acceptation ni de refus, pas d’état « contre-proposition en attente » ; V17 : « Commission 1 % » figée, carte agent en 1 %, partenaires déménagement (C3) ; aucun écran : liste des offres, vente annulée, vente « Vendu », lot ; barres d’onglets sur V12b / V15 / V17 alors que les écrans de vente d’EPIC-08 sont plein écran ; apostrophes droites `L'Expert`.

## 11. Questions ouvertes (réponse du porteur de projet attendue)

Légende : **🔴 bloquante** · **🟢 défaut réversible** (option recommandée codée, changeable ensuite).

**Aucune question ne bloque le codage d’EPIC-10.** Q8 (portée juridique de l’acceptation) est 🔴 **avant tout vrai vendeur ou acquéreur**, pas avant le code.

1. **Offres sous L’Expert (spec Q8)** 🟢 — (a) **le vendeur voit V16 et décide ; l’agent conseille (bloc « Conseil de votre agent »)** (recommandé) ; (b) l’agent négocie, le vendeur n’accepte que l’offre finale ; (c) au choix, offre par offre.
2. **Vues et favoris (spec Q13)** 🟢 — (a) **masqués tant que l’app acquéreur n’existe pas** (recommandé) ; (b) chiffres saisis par l’équipe ; (c) affichés à 0.
3. **Diffusion** 🟢 — (a) **seulement « Realesty · En ligne »** (recommandé) ; (b) portails listés « Bientôt ».
4. **Offres concurrentes quand j’en accepte une** 🟢 — (a) **les autres offres en attente sont refusées (« Une autre offre a été acceptée »)** (recommandé) ; (b) gardées « en secours » ; (c) le vendeur choisit.
5. **Bornes de la contre-proposition** 🟢 — (a) **au-dessus de l’offre et au plus le prix affiché (maquette)** (recommandé) ; (b) au-dessus de l’offre, sans plafond ; (c) libre.
6. **Validité** 🟢 — (a) **7 jours pour une offre (modifiable par l’équipe) et pour une contre-proposition ; expiration automatique horaire** (recommandé) ; (b) 72 h pour une contre-proposition ; (c) pas d’expiration.
7. **Nombre de tours** 🟢 — (a) **illimité, une proposition en attente à la fois par fil** (recommandé) ; (b) 3 tours maximum.
8. **Portée juridique de l’acceptation** 🔴 (avant tout vrai vendeur ; pas avant le code) — (a) **phase de test : offres `is_test` avec bandeau, texte neutre « votre conseiller prévient l’acquéreur et le notaire », validation par un juriste avec le montage du mandat** (recommandé) ; (b) acceptation « sous réserve de signature du compromis » rédigée par un juriste dès maintenant ; (c) pas d’acceptation dans l’app : le vendeur « donne son accord » et l’équipe formalise.
9. **Annonce et visites après acceptation** 🟢 — (a) **annonce en ligne « Sous offre », visites encore possibles ; au compromis : annonce hors ligne, demandes refusées, visites futures annulées** (recommandé) ; (b) hors ligne dès l’acceptation.
10. **Retrait après acceptation** 🟢 — (a) **impossible dans l’app (« Contactez votre conseiller ») ; l’équipe annule (`staff_cancel_deal`)** (recommandé) ; (b) possible avec confirmation.
11. **Lot vendu en entier** 🟢 — (a) **une offre porte sur le lot ; ventilation par bien saisie par l’équipe au compromis si le notaire la demande** (recommandé) ; (b) prix par bien dans chaque offre. Pas d’offre partielle sur un bien d’un lot vendu en entier (retirer puis vendre bien par bien).
12. **Notaire** 🟢 — (a) **saisi par l’équipe ; le vendeur l’indique à son conseiller** (recommandé) ; (b) le vendeur le saisit dans V17.
13. **Agent L’Expert** 🟢 — (a) **l’équipe Realesty joue l’agent (contact saisi par l’équipe) jusqu’aux agences partenaires (P-écrans)** (recommandé, cohérent avec EPIC-08 Q17) ; (b) une agence partenaire réelle dès maintenant.
14. **Dates du suivi** 🟢 — (a) **saisies par l’équipe d’après le notaire ; fin de rétractation pré-calculée (signature + 10 jours) affichée « indicative » tant qu’elle n’est pas confirmée** (recommandé) ; (b) toutes calculées.
15. **Archivage des offres** 🟢 — (a) **chaque offre est une ligne horodatée montrée dans le coffre-fort (« Mandats & visites »), pas de PDF en v1** (recommandé) ; (b) PDF généré (`render-offer`).
16. **Commission affichée** 🟢 — (a) **taux de la formule × prix (offre acceptée puis acte), « indicatif, rien n’est prélevé dans l’app »** (recommandé) ; (b) masquée en phase de test.
17. **Barre d’onglets sur V12b / V15 / V17** 🟢 — (a) **plein écran au-dessus des onglets, comme les écrans de vente d’EPIC-08 (écart signalé)** (recommandé : une seule pile par vente) ; (b) routes dans la branche « Mon bien » avec barre visible.
18. **« Message » / « Écrire »** 🟢 — (a) **`mailto:` / `tel:` vers le contact saisi** (recommandé) ; (b) masqués ; (c) messagerie in-app (plus tard).
19. **Bien vendu** 🟢 — (a) **reste dans « Mes biens » avec « Vendu le … », en lecture seule ; ne peut pas être remis en vente** (recommandé) ; (b) archivé et masqué.
20. **Échec du compromis ou du prêt** 🟢 — (a) **l’équipe annule : offre « annulée », vente republiée, notification** (recommandé) ; (b) la vente revient « Mandat signé » et le vendeur republie lui-même.

### 11.1 Questions de la spec V8b–V19 (§7) concernées

| # spec | Sujet | Statut |
|---|---|---|
| Q8 | Offres sous L’Expert | **Ici Q1** |
| Q13 | Vues et favoris | **Ici Q2** |
| Q18 | Résiliation / retrait | EPIC-08 Q15 (défaut codé) ; après acceptation : **ici Q10** |

---

## Journal d’exécution

_(vide — à remplir tranche par tranche)_
