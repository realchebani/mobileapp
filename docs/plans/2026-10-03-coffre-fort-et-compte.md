# EPIC-11 · Coffre-fort & compte (C1, V18, C2, V19, notifications) — plan d’implémentation

> Date : 2026-10-03. Statut : **livré** (tranches K1–K10, voir le journal d’exécution ; arbitrages en fin de document).
> Sources lues : `CLAUDE.md`, `docs/decisions.md`, `docs/epics/*.md`, [spec V8b → V19](2026-10-01-parcours-vendeur-v8b-v19.md) (§3 C1, V18, C2, V19, 3.13 ; §4.5 ; §6 EPIC-11 ; §7 Q11, Q14–Q17 ; §9), [plan multi-biens](2026-10-02-multi-biens.md), `supabase/migrations/*` (`create_profiles`, `create_seller_tunnel`, `lock_submitted_dossiers`, `lock_document_files`, `valuations_and_notifications`, `multi_biens*`, `room_photos` d’EPIC-15), `lib/seller_space/**` (`account/account_page.dart`, `notifications/**`, `coming_soon/`), `lib/seller_tunnel/steps/documents/**`, `packages/sale_repository`, `packages/profile_repository`, maquettes `CoffreFort`, `CoffreDossier`, `EspaceAdmin`, `MonCompteProfil` (`scratchpad/seller-design-next/project/*.dc.html`).
> Plans frères (même date) : [Formules & mise en vente](2026-10-03-offres-et-mise-en-vente.md) (EPIC-08), [Back-office expert](2026-10-03-back-office-expert.md) (EPIC-12).

---

## 0. Contexte et périmètre

Aujourd’hui : l’onglet **Coffre-fort** (`/vendeur/coffre`) est un écran « Bientôt » ; l’onglet **Compte** (C2 v1, `AccountPage`) affiche nom, e-mail, rôle, méthode de connexion, langue (lecture seule), déconnexion et le lien design system en développement. Les documents d’un bien sont saisis en V7 (`property_documents`, bucket privé `property-documents` sous `<uid>/<property id>/…`) et **verrouillés dès que le dossier passe `in_review`** (RLS lignes + Storage). Les notifications in-app existent (cloche, feuille, `notifications.read_at`). Il n’y a ni modification du profil, ni suppression de compte — or **l’App Store exige la suppression du compte depuis l’app** (règle 5.1.1(v)) pour toute app qui permet d’en créer un.

**Dans le périmètre d’EPIC-11** :
- **C1 / V18 · coffre-fort par bien (et par lot)** : rubriques, compteurs, statuts, recherche, récents, détail d’un document (aperçu, télécharger, remplacer), **ajout de documents après le verrouillage**, **visibilité** par document (acquéreurs certifiés / notaire — préférence enregistrée, effective avec le côté acquéreur), documents produits par Realesty (avis de valeur, mandats d’EPIC-08) ;
- **C2 / V19 · compte** : profil (prénom, nom, téléphone, adresse postale), **e-mail en lecture seule**, méthode de connexion, **langue**, **suppression du compte**, **liste des notifications** ;
- fonctions `staff_*` de vérification / refus d’un document (enveloppées ensuite par le back-office EPIC-12).

**Hors périmètre** : chiffrement de bout en bout, OCR / « Informations extraites » (affichées seulement si `extracted` existe), facturation et moyens de paiement (aucun paiement en v1), Face ID / 2FA / mot de passe / Apple / Google, invitation des co-propriétaires, « Profil actif » acquéreur, espace acquéreur du coffre-fort, notifications push ou e-mail.

## 1. Décisions déjà prises

| Décision | Source | Conséquence ici |
|---|---|---|
| **Notifications dans l’app uniquement** | `decisions.md` 2026-10-01 | Une liste complète dans Compte ; aucune préférence push / e-mail. |
| **Barre d’onglets dès le début**, déconnexion dans Compte | `decisions.md` 2026-10-01 | Coffre-fort et Compte sont des racines d’onglet existantes : on remplace leur contenu. |
| **E-mail en lecture seule** (pas de changement d’adresse dans l’app en v1) | brief du porteur de projet (2026-10-03), spec Q16 | Champ grisé + « Pour changer d’adresse, contactez-nous ». |
| **Suppression du compte dans l’app** | règle App Store 5.1.1(v) | Écran dédié + Edge Function `delete-account` (Q8 : modalités). |
| **Paiements : aucun en v1** | `decisions.md` 2026-10-01 | Rubrique « Facturation » et lignes « Paiements » / « Factures » masquées (Q13). |
| **Plusieurs biens & lots** (EPIC-13) ; pièce d’identité **copiée** d’un bien à l’autre | `decisions.md` 2026-10-02, EPIC-13 Q1 | Le coffre-fort est organisé **par bien**, avec une vue de lot (Q1). |
| **Certification par back-office web** (EPIC-12), confidentialité | `decisions.md` 2026-10-01 | Statuts « Vérifié expert » / « Refusé » écrits par l’équipe ; journal des consultations par l’équipe (EPIC-12) qui rend vraie la mention « chaque ouverture est enregistrée » (Q5). |
| **Mandat de test** (EPIC-08) | `decisions.md` 2026-10-01 | Le PDF « SPÉCIMEN » apparaît dans « Mandats & visites » quand EPIC-08 est livré. |
| Une branche / PR par epic | `decisions.md` 2026-10-01 | `feat/epic-11-coffre-fort-compte`. |

## 2. Modèle de données — migration `AAAAMMJJhhmmss_coffre_fort_compte.sql`

### 2.1 `property_documents` (extension)

| Changement | Détail |
|---|---|
| `kind` | check étendu : + `dpe`, `contrat_entretien`, `assurance`, `copropriete` (règlement / PV d’AG, utile aux appartements et immeubles). Les types produits par Realesty (`mandat`, `offre`, `compromis`, `compte_rendu`) ne sont **pas** des `property_documents` : ils restent dans leurs tables / buckets (avis de valeur : `valuations` ; mandat : `mandates`, EPIC-08) et sont montrés comme lignes virtuelles (§4.3). |
| `title` | text ≤ 120, libellé libre du vendeur (grant update) |
| `owner_ref` | uuid null → `property_owners` on delete set null : à qui appartient une pièce d’identité (« Identité · 0 document sur 2 ») (grant insert / update) |
| `visibility` | text[] not null default `'{}'` check `<@ array['buyers','notary']` — **sans grant** : modifiée par RPC |
| `added_after_lock` | bool not null default false — posé par trigger, sans grant |
| `verified_at`, `verified_by` | timestamptz / uuid — équipe seulement |
| `rejected_reason` | text ≤ 300 — équipe seulement (statut `rejected` existant) |
| `replaced_by` | uuid null → `property_documents` on delete set null : un document refusé remplacé pointe vers le nouveau (sans grant, posé par RPC) |

Triggers :
- `property_documents_before_insert` : `added_after_lock := parent.status not in ('draft', 'submitted')` ; `visibility := '{}'` pour `piece_identite` (« Privé · non partageable »).
- Le check de `visibility` refuse toute valeur non vide pour `piece_identite` (double sécurité).

RLS (en plus des politiques existantes, qui restent valables pour `draft` / `submitted`) :
- **insert après verrouillage** : nouvelle politique permissive « Owners can add documents to locked properties » : propriétaire, `status in ('in_review', 'certified')` ; la politique restrictive existante (`storage_path like uid || '/%'`) s’applique toujours ; une politique restrictive supplémentaire impose `storage_path like uid || '/' || property_id || '/%'`.
- **suppression après verrouillage** : seulement si `added_after_lock and verified_at is null` (Q3).
- **update** après verrouillage : `title` seulement (grant de colonne + politique `added_after_lock or status in (draft, submitted)` pour `kind`).
- Les documents présents au moment de la prise en charge restent **verrouillés** (comportement actuel inchangé).

Storage `property-documents` : nouvelle politique d’insert « Owners can add documents to their locked properties » : 1ᵉʳ segment = uid, 2ᵉ segment = un bien de l’utilisateur à **n’importe quel statut** ; **pas d’update** (pas d’écrasement) ; delete seulement si une ligne `property_documents` `added_after_lock and verified_at is null` pointe sur l’objet (`storage_path = name`). Les photos d’EPIC-15 (`…/photos/…`) restent verrouillées : la politique exclut `(storage.foldername(name))[3] = 'photos'`.

### 2.2 RPC (`security definer`, `authenticated`)

| Fonction | Contrôles | Effet |
|---|---|---|
| `set_document_visibility(p_document_id uuid, p_visibility text[])` | document d’un bien de l’appelant ; refus pour `piece_identite` ; valeurs autorisées | met à jour `visibility` (tout statut : choix de partage, pas une donnée du dossier) |
| `replace_document(p_old_id uuid, p_new_id uuid)` | les deux documents au même bien de l’appelant ; l’ancien `rejected` ou ajouté après verrouillage non vérifié | `replaced_by` ; l’ancien, s’il était ajouté après verrouillage, est supprimé par l’app ensuite |

Fonctions équipe (`security invoker`, exécution retirée aux rôles client, SQL Editor jusqu’à EPIC-12) : `staff_verify_document(p_document_id)` (→ `verified_at`, statut `analyzed`, notification `document_verified` facultative) et `staff_reject_document(p_document_id, p_reason)` (→ `rejected`, `rejected_reason`, notification `document_rejected` « Un document est à remplacer », route `/vendeur/coffre/<property id>?rubrique=<code>`). Runbook `certifier-un-dossier.md` complété (§ « Vérifier ou refuser un document »).

### 2.3 `profiles` (extension)

+ `last_name` text ≤ 100, `phone` text ≤ 20 (format FR / international vérifié dans l’app, `check (phone ~ '^\+?[0-9 .]{6,20}$')`), `postal_address` text ≤ 300, `locale` text null check in (`fr`, `en`, `es`) (null = langue de l’appareil). Grant update sur ces colonnes. `first_name` existe déjà.

### 2.4 `notifications`

- Contrôle `kind` remplacé, **de façon idempotente**, par le format `^[a-z][a-z_]{2,39}$` (même instruction dans les trois plans frères : l’ordre de fusion est indifférent).
- Nouveaux types EPIC-11 : `document_rejected`, `document_verified`.
- Index existant `(user_id, created_at desc)` suffisant pour une liste paginée.

### 2.5 Journal des suppressions de compte

`account_deletions` : `id`, `user_id` (uuid, **sans clé étrangère**), `email_sha256` text, `deleted_at`, `properties_count` int, `files_count` int, `requested_from` text (`app`). RLS activée, **aucune politique** (service role seulement). Sert à prouver la suppression et à empêcher un traitement en double ; ne contient aucune donnée personnelle en clair (Q8).

### 2.6 Sonde RLS (bloc `DO` annulé)
Propriétaire : ajoute un document à un bien `in_review` / `certified` ✔ (ligne + objet), le supprime ✔, supprime un document d’origine ✘, écrase un fichier verrouillé ✘, écrit dans `…/photos/` d’un bien verrouillé ✘, rend une pièce d’identité visible ✘, change `verified_at` / `added_after_lock` ✘, ajoute dans le dossier d’un autre ✘ ; modifie `profiles.phone` ✔, `profiles.role` ✔ (existant), le profil d’un autre ✘ ; lit `account_deletions` ✘ ; autre utilisateur et `anon` ne voient rien.

## 3. Fonctions serveur

### 3.1 Edge Function `delete-account` (nouvelle, Deno)
- `POST` avec le JWT de l’appelant et `{ "confirmation": "SUPPRIMER" }` ; `verify_jwt` actif.
- Préconditions (Q8) : l’appelant n’est pas membre de l’équipe (EPIC-12 : `staff_members` — refus `staff_account`) ; s’il a une vente active d’EPIC-08 (`sales.stage in ('mandate_signed', 'published')`), refus `active_sale` avec le message « Retirez d’abord votre bien de la vente » (en test, mandat sans valeur : option de retrait automatique, Q8).
- Étapes (service role) : 1) lister et supprimer, page par page, les objets sous `<uid>/` de **tous** les buckets privés (`property-documents`, `valuation-reports`, et s’ils existent `listing-media`, `mandate-signatures`, `sale-documents`) ; 2) insérer `account_deletions` ; 3) `auth.admin.deleteUser(uid)` → cascades existantes (`profiles`, `properties` et enfants, `property_lots`, `notifications`, `agent_sessions` / `agent_turns`, `vision_requests`, `valuations` via `properties`) ; `valuations.expert_user_id` passe à null pour un expert.
- Idempotente : un second appel après une suppression partielle reprend les fichiers restants. Réponses typées (`{ok:true}`, `staff_account`, `active_sale`, `bad_confirmation`, `server_error`).
- Tests Deno : client Supabase factice (liste paginée, ordre des étapes, refus).
- Aucune donnée n’est conservée « au cas où » ; la rétention légale de documents contractuels (mandats réels, factures) sera traitée quand ils existeront (aujourd’hui : mandats de test seulement).

### 3.2 Liens signés
Aperçu et téléchargement : URL signées de 5 min créées par l’app (RLS Storage existante, lecture du dossier `<uid>/`). Les documents Realesty : `valuation-reports` (existant), `sale-documents` (EPIC-08).

## 4. Écrans et parcours

| Écran | Route | Maquette | Remarque |
|---|---|---|---|
| C1 Coffre-fort | `/vendeur/coffre` (racine d’onglet) | `CoffreFort.dc.html` | remplace `ComingSoonPage.vault` |
| V18 Mes documents (un bien ou un lot) | `/vendeur/coffre/biens/<propertyId>?rubrique=<code>` · `/vendeur/coffre/lots/<lotId>` | `CoffreDossier.dc.html` | enfant de l’onglet (barre visible) |
| Détail d’un document | feuille | `CoffreDossier` (feuille détail) | |
| Ajouter un document | feuille → scanner / importer | — (réutilise V7) | |
| C2 Mon compte | `/vendeur/compte` | `EspaceAdmin.dc.html` | refonte de `AccountPage` |
| V19 Informations & sécurité | `/vendeur/compte/profil` | `MonCompteProfil.dc.html` | plein écran |
| Notifications | `/vendeur/compte/notifications` | **absent du canevas** | plein écran |
| Langue | feuille | **absent du canevas** | |
| Supprimer mon compte | `/vendeur/compte/suppression` | **absent du canevas** | plein écran |

### 4.1 C1 · Coffre-fort (`VaultPage`)
- Titre « Coffre-fort » + « Ajouter un document » ; segment « Espace vendeur · Espace acquéreur » **masqué** (pas de côté acquéreur).
- **Sélecteur de bien** (Q1) quand le vendeur a plusieurs biens : puce « Maison · Chaponost ▾ » ouvrant la liste des biens et des lots (« Lot : Maison + terrain ») ; avec un seul bien, aucun sélecteur ; le choix est mémorisé (préférence locale).
- Recherche « Rechercher un document » (filtre local sur titre, type, nom de fichier).
- Rubriques (lignes `RealestyListItem` → V18 ouverte sur la rubrique) avec compteurs et statut : Propriété (`titre_propriete`, `plan`, `copropriete`), Fiscalité (`taxe_fonciere`), Énergie (`diagnostics`, `dpe`, `facture_energie`, `contrat_entretien`), Travaux (`facture_travaux`, `rapport_spanc`, `assurance`), Identité (`piece_identite`, « 2 à ajouter » = propriétaires sans pièce via `owner_ref`), Mandats & visites (avis de valeur, mandats — virtuels), Autres (`autre`) ; **Facturation masquée** (Q13).
- « Récents » : 3 derniers documents (tous types), badge de statut ; pièce d’identité manquante → « Manquant » + « Scanner ».
- Pied : texte selon Q5 (par défaut « Documents chiffrés et stockés en Europe. Accès limité à vous et à l’équipe Realesty en charge du dossier. »).
- États : chargement, erreur avec « Réessayer », aucun bien (« Ajoutez un bien pour ranger vos documents » → « Ajouter un bien »), tirer pour actualiser.

### 4.2 V18 · Mes documents (`VaultDocumentsPage`)
- En-tête « Coffre-fort · Espace vendeur », titre « Mes documents » (+ nom du bien / lot), « Ajouter un document » ; compteurs « 14 documents » « 2 à ajouter » ; « Tout replier ».
- `AgentBubble` contextuelle **statique** (règles) : pièce d’identité manquante → « Il manque votre pièce d’identité pour signer le mandat. Scannez-la en 30 secondes. » (sans « je vérifie automatiquement ») ; document refusé → « L’expert demande de remplacer : {titre} ({motif}) ».
- `CollapsibleSection` par rubrique (titre, compteur, résumé « 3 documents · tous vérifiés », badge « À compléter » / « 3/3 ») ; ligne document : titre (ou libellé du type), sous-titre (« PDF · 2 pages · ajouté le 12/09/2026 », « Ajouté après l’envoi »), badge de statut (`received` → « Reçu », `analyzing` → « Analyse en cours », `analyzed` → « Analysé », `verified_at` → « Vérifié expert », `rejected` → « À remplacer »), puce de visibilité (« Privé », « Acquéreurs », « Notaire », « Acquéreurs · Notaire », aria « Qui peut voir ce document : … ») ; ligne manquante → « Scanner ».
- **Vue lot** : mêmes rubriques, chaque ligne porte le bien (« Garage · »), ajout = choix du bien d’abord.
- Documents Realesty en lecture seule : « Avis de valeur certifié » (`valuations.report_storage_path`, « Validé le 25/09 par Julien M. », « Vérifié expert ») ; « Mandat de vente (test) » (EPIC-08, si présent).

### 4.3 Détail d’un document (feuille `VaultDocumentSheet`)
- Aperçu : miniature pour une image ; icône PDF + « Ouvrir » (URL signée dans le navigateur intégré, `url_launcher` `inAppBrowserView`) ; titre modifiable (crayon), type, taille, date, « Ajouté après l’envoi » ; « Informations extraites » seulement si `extracted` non vide (`ProvenanceTag.document`).
- Motif de refus (`InlineBanner.warning`) + « Remplacer ».
- « Qui peut voir ce document ? » : `SwitchRow` « Acquéreurs certifiés » / « Dans la fiche détaillée, après Pass Visite » et « Notaire » / « Transmis au compromis » → `set_document_visibility` ; mention « Ces réglages s’appliqueront quand les acquéreurs et le notaire auront accès à Realesty. » (rien n’est partagé aujourd’hui) ; pièce d’identité : « Privé · non partageable », interrupteurs absents.
- Actions : « Télécharger » (Q12 : feuille de partage iOS), « Remplacer » (document non verrouillé ou refusé), « Supprimer » (non verrouillé ; confirmation intégrée).

### 4.4 Ajouter un document
Feuille « Ajouter un document » : rubrique → type (libellés de V7, `document_labels.dart`) → (pièce d’identité : pour quel propriétaire) → « Scanner » (VisionKit, multipage → PDF, `scan_pdf_builder`) / « Importer » (`file_selector`) / « Depuis un autre bien » (copie Storage, EPIC-13). Avant verrouillage, l’ajout est identique à V7 (même dossier) ; après, la ligne est marquée « Ajouté après l’envoi » et l’expert la voit (back-office). Le code de capture de V7 est **extrait** dans un module partagé `lib/documents/` (picker, scan, PDF, réutilisation) pour servir V7 et le coffre-fort sans dupliquer — tranche K3.

### 4.5 C2 · Mon compte (`AccountPage`, refonte)
D’après `EspaceAdmin.dc.html` :
- Carte identité : initiales, « Prénom Nom », e-mail, badge « Vendeur·se » (selon Q11 pas de badge acquéreur), bouton modifier → V19.
- « Profil actif Vendeur · Acquéreur » **masqué** (Q11).
- « Mon dossier vendeur » : « Propriétaires » (bien courant ou liste des biens → V19 section propriétaires) ; « Ma formule » (EPIC-08 : formule + statut → la vente ; masqué sans vente) ; « Paiements » et « Factures Realesty » **masqués**.
- « Mon projet d’achat » et « Mes partenaires » **masqués**.
- « Connexion & sécurité » : « Informations personnelles » → V19 ; « Méthode de connexion » « Lien de connexion par e-mail » (lecture seule) ; Face ID, double authentification, appareils connectés **masqués** (Q6).
- « Préférences » : « Notifications » → liste (§4.7) avec pastille du nombre de non lues ; « Langue » → feuille (§4.8) ; « Agent IA · Mode vocal par défaut » masqué (EPIC-14/16 en décident).
- « Confidentialité » : « Mes données » → « Supprimer mon compte » (§4.9) (l’export viendra plus tard).
- « Se déconnecter » ; lien Design system (development).

### 4.6 V19 · Informations & sécurité (`ProfilePage`)
- Avatar initiales ; « Changer la photo » masqué.
- « Mes informations » : Prénom, Nom, E-mail (lecture seule, aide « Pour changer d’adresse e-mail, écrivez-nous à … »), Téléphone (clavier téléphone), Adresse postale (texte libre, Q14) ; bouton collant **« Enregistrer les modifications »** (maquette), motif du tunnel (toujours actif, erreurs affichées, défilement vers la première, délai 15 s, champs désactivés pendant l’envoi) ; retour sans enregistrer → feuille « Quitter sans enregistrer ? » intégrée.
- « Propriétaires du bien » (bien courant) : lignes « {Nom} (vous) » + statut d’identité (« Vérifiée » si `identity_verified_at`, EPIC-08 ; sinon « Pièce reçue » / « À ajouter ») ; « Inviter un co-propriétaire » masqué. Les propriétaires d’un dossier ne sont **pas** modifiés par le profil (Q10).
- « Sécurité » : seulement « Méthode de connexion : lien par e-mail » ; « Pièce d’identité · Requise pour signer le mandat · À ajouter » → V18 Identité.
- « Supprimer mon compte » (texte rouge) → §4.9.

### 4.7 Notifications (`NotificationsPage`, non dessinée)
- Liste plein écran de toutes les notifications (tous biens), groupées « Aujourd’hui / Cette semaine / Plus ancien », point non lu, nom du bien concerné (comme la feuille actuelle), toucher → route ; « Tout marquer comme lu » ; pagination (50 par page, « Voir plus »).
- La feuille de la cloche (EPIC-07) garde les 10 dernières + « Tout voir » → cette page.
- Aucun réglage push / e-mail (Q9).

### 4.8 Langue (feuille `LanguageSheet`)
« Langue de l’appareil (Français) », « Français », « English », « Español » ; choix appliqué tout de suite via un `LocaleCubit` au-dessus de `MaterialApp.router` (`locale:`), mémorisé dans `shared_preferences` et `profiles.locale` (Q7). Les notifications déjà créées restent dans la langue de leur création (texte écrit côté serveur, en français) — limite signalée.

### 4.9 Supprimer mon compte (`DeleteAccountPage`, non dessinée)
- Ce qui sera supprimé : profil, biens et dossiers (n), documents et photos, avis de valeur, notifications, historique de l’agent vocal ; « Cette action est définitive. »
- Blocage expliqué s’il y a une vente active (EPIC-08) : bouton « Retirer mon bien de la vente ».
- Saisie de « SUPPRIMER » + bouton rouge « Supprimer définitivement mon compte » → `delete-account` → déconnexion locale (`AppBloc`), retour à l’accueil (01) avec le message « Votre compte a été supprimé ». Échec : message + « Réessayer » ; l’appel est idempotent.

## 5. Données côté app

- **`property_repository`** : `PropertyDocument` étendu (`title`, `ownerRef`, `visibility`, `addedAfterLock`, `verifiedAt`, `rejectedReason`, `replacedBy`), `listDocuments(propertyIds)`, `addDocument` (existant, réutilisé après verrouillage), `setDocumentVisibility`, `renameDocument`, `replaceDocument`, `deleteDocument` (existant), `documentUrl`.
- **`profile_repository`** : `Profile` + `lastName`, `phone`, `postalAddress`, `locale` ; `updateProfile(patch)`.
- **`auth_repository`** : `deleteAccount()` (`functions.invoke('delete-account')`, échecs typés `AccountDeletionFailure(reason)`), puis déconnexion locale.
- **`sale_repository`** : `NotificationRepository.getNotifications(before:, limit:)` (pagination), `markAllRead()` ; `AppNotificationKind` + `documentRejected`, `documentVerified`.
- Vue « coffre-fort » côté app : `VaultCubit` (biens / lots, documents, avis de valeur, mandats si `SaleRepository` les fournit) et modèle pur `VaultCategory.of(kind)` (rubriques, documents requis par type de bien via `PropertyTypeProfile`).
- `lib/seller_space/vault/**`, `lib/seller_space/account/**` (`profile/`, `notifications/`, `language/`, `deletion/`), `lib/app/locale/` (`LocaleCubit`), `lib/documents/**` (module partagé extrait de V7).
- Design system : `CollapsibleSection`, `RealestySwitch` / `SwitchRow` (si EPIC-08 ne l’a pas encore livré : la première tranche qui en a besoin l’ajoute, l’autre réutilise).
- l10n : `vault*`, `vaultDoc*`, `account*`, `profile*`, `notificationsPage*`, `language*`, `deleteAccount*`.

## 6. User stories (EPIC-11)

- **US-11.1 · Coffre-fort par rubriques (C1)** — *En tant que vendeur, je veux retrouver les documents de chaque bien par rubrique.*
  - Rubriques avec compteurs et statut, recherche, 3 récents ; documents manquants requis (titre de propriété, pièce d’identité de chaque propriétaire) signalés « Manquant » avec « Scanner ».
  - Plusieurs biens : je choisis le bien ou le lot ; un seul bien : pas de sélecteur.
  - Avis de valeur (et mandat d’EPIC-08) visibles en lecture seule dans « Mandats & visites ».
- **US-11.2 · Mes documents d’un bien (V18)** — sections repliables, statut (Reçu, Analyse en cours, Analysé, Vérifié expert, À remplacer + motif), visibilité, documents ajoutés après l’envoi signalés ; vue lot avec le bien de chaque document.
- **US-11.3 · Ajouter un document à tout moment** — *En tant que vendeur, je veux ajouter un document même après l’envoi (pièce manquante, diagnostics, document refusé).*
  - Scanner (multipage → PDF), importer ou reprendre d’un autre bien, comme en V7.
  - Après l’envoi : document marqué « Ajouté après l’envoi », visible par l’expert ; les documents d’origine restent verrouillés.
  - Je peux supprimer ou remplacer un document que j’ai ajouté après l’envoi tant qu’il n’est pas vérifié.
- **US-11.4 · Détail et téléchargement** — aperçu, ouverture du PDF, titre modifiable, télécharger (partage iOS), remplacer / supprimer selon les règles.
- **US-11.5 · Qui peut voir ce document** — interrupteurs Acquéreurs certifiés / Notaire enregistrés ; pièce d’identité toujours privée ; mention claire que rien n’est encore partagé.
- **US-11.6 · Mon compte (C2) et mes informations (V19)** — prénom, nom, téléphone, adresse postale modifiables avec validation ; e-mail en lecture seule ; méthode de connexion affichée ; propriétaires du bien et statut d’identité ; lien vers la pièce d’identité ; éléments sans objet en v1 masqués.
- **US-11.7 · Langue** — je choisis Français, English, Español ou la langue de l’appareil ; l’app change immédiatement et s’en souvient.
- **US-11.8 · Notifications** — liste complète, groupée par date, avec le bien concerné ; ouverture de l’écran lié ; tout marquer comme lu ; « Tout voir » depuis la cloche.
- **US-11.9 · Supprimer mon compte** — *En tant qu’utilisateur, je veux supprimer mon compte et mes données depuis l’app.*
  - Écran listant ce qui sera supprimé, saisie « SUPPRIMER », suppression définitive des fichiers puis du compte, déconnexion et message de confirmation.
  - Refus expliqué si une vente est active (ou retrait automatique, Q8) ; un membre de l’équipe ne peut pas supprimer son compte depuis l’app.
- **US-11.10 · Vérification par l’équipe (avant EPIC-12)** — `staff_verify_document` / `staff_reject_document` + runbook ; le vendeur reçoit « Un document est à remplacer » qui ouvre la bonne rubrique.

## 7. Découpage

| # | Tranche | Fichiers possédés | Dépend de |
|---|---|---|---|
| K1 | Migration `*_coffre_fort_compte.sql` (§2) + essai annulé + sonde RLS + `db push` ; runbook (vérifier / refuser un document) | `supabase/migrations/*_coffre_fort_compte.sql`, `docs/runbooks/certifier-un-dossier.md` (section ajoutée) | Q2, Q3 |
| K2 | Dépôts : `property_repository` (documents), `profile_repository`, `auth_repository.deleteAccount`, `sale_repository` (pagination notifications) + tests | `packages/{property,profile,auth,sale}_repository/**` (fichiers documents / profil / suppression / notifications seulement) | K1 |
| K3 | Extraction du module documents de V7 vers `lib/documents/` (aucun changement de comportement V7, tests déplacés) | `lib/documents/**`, `lib/seller_tunnel/steps/documents/{data,scan,widgets/reuse_document_sheet.dart}` (déplacés), imports V7 | — (à faire quand aucune autre branche ne touche V7) |
| K4 | C1 `VaultPage` + `VaultCubit` + `VaultCategory` + sélecteur de bien / lot + routes | `lib/seller_space/vault/{vault_page,cubit,models}/**`, `lib/app/router/**` (branche Coffre-fort), ARB `vault*` | K2 |
| K5 | V18 + feuille détail + visibilité + ajout / remplacement / suppression | `lib/seller_space/vault/{documents,detail,add}/**`, `lib/ui/components/collapsible_section.dart`, ARB `vaultDoc*` | K3, K4 |
| K6 | C2 refonte + V19 profil | `lib/seller_space/account/**` (sauf `notifications/`, `language/`, `deletion/`), ARB `account*`, `profile*` | K2 |
| K7 | Langue : `LocaleCubit`, feuille, `MaterialApp.router(locale:)` | `lib/app/locale/**`, `lib/app/view/app.dart`, `lib/seller_space/account/language/**` | K6 |
| K8 | Page Notifications + « Tout voir » dans la feuille | `lib/seller_space/account/notifications/**`, `lib/seller_space/notifications/notifications_sheet.dart`, `lib/seller_space/cubit/notifications_*` | K2 |
| K9 | Edge Function `delete-account` + tests Deno + déploiement ; écran de suppression | `supabase/functions/delete-account/**`, `supabase/functions/tests/delete_account_test.ts`, `lib/seller_space/account/deletion/**` | K2, Q8 |
| K10 | Intégration : `app_test.dart` (coffre-fort, compte, suppression), `CLAUDE.md`, epic, journal ; contrôle iPhone | `test/app/view/app_test.dart`, docs | toutes |

Vagues : **{K1, K3}** → **{K2}** → **{K4, K6, K8, K9}** → **{K5, K7}** → **{K10}**. ARB sérialisés.

Coordination : EPIC-08 ajoute « Ma formule » (C2) et les mandats (C1) — chaque côté masque l’élément si l’autre n’est pas fusionné (`isRouteAvailable` / dépôt optionnel). EPIC-12 enveloppe `staff_verify_document` / `staff_reject_document` et alimente le journal des consultations (Q5).

## 8. Risques

| Risque | Parade |
|---|---|
| Rouvrir l’écriture sur des dossiers verrouillés (RLS) | Politiques additionnelles **étroites** (insert seulement, pas d’écrasement, suppression limitée aux ajouts non vérifiés, dossier `photos/` exclu) + sonde RLS complète. |
| Suppression de compte incomplète (fichiers orphelins) ou trop large | Fichiers d’abord, page par page, sur tous les buckets ; idempotence ; tests Deno ; journal `account_deletions` ; essai sur un compte de test avant publication. |
| Rejet App Store sans suppression in-app | US-11.9 dans la première PR utilisable ; parcours testé sur iPhone. |
| Mentions de confidentialité fausses (« bout en bout », « chaque ouverture enregistrée ») | Texte corrigé (Q5) tant que le chiffrement n’existe pas ; mention du journal seulement quand EPIC-12 enregistre les consultations. |
| Extraction du module documents de V7 en conflit avec EPIC-15 / EPIC-16 | K3 planifiée hors de leurs fenêtres, sans changement de comportement ; repli : le coffre-fort importe les fichiers V7 sans les déplacer. |
| Changement de langue : textes serveur (notifications) en français | Limite documentée ; textes d’affichage par clé l10n côté app à étudier plus tard (`kind` + paramètres). |
| Écrans non dessinés (notifications, langue, suppression, sélecteur de bien) | Design system ; liste pour le canevas. |

## 9. Écarts de maquette à signaler
C1 / V18 « Chiffrement de bout en bout » et « chaque ouverture est enregistrée » ; V18 « je vérifie automatiquement » ; C2 / V19 sécurité (Face ID, 2FA, mot de passe, Apple / Google) ; « Profil actif » ; Facturation et SEPA ; pas d’écran : liste des notifications, langue, suppression du compte, sélecteur de bien du coffre-fort, ajout de document ; V19 « Inviter un co-propriétaire ».

## 10. Questions ouvertes

Légende : **🔴 bloquante** · **🟢 défaut réversible**.

1. **Organisation du coffre-fort avec plusieurs biens** 🟢 — (a) **sélecteur de bien / lot en haut de C1, rubriques du bien choisi ; vue lot agrégée** (recommandé) ; (b) rubriques communes à tous les biens, chaque document étiqueté par bien ; (c) une ligne par bien dans C1, puis ses rubriques (un niveau de plus).
2. **Ajout après verrouillage : quels documents, quel effet ?** 🔴 (avant K1) — (a) **tous les types, marqués « Ajouté après l’envoi », sans changer le statut du dossier ; l’expert les voit dans le back-office** (recommandé) ; (b) seulement les types manquants ou refusés ; (c) tout ajout repasse le dossier en « à revoir » (statut supplémentaire).
3. **Supprimer / remplacer après verrouillage** 🔴 (avant K1) — (a) **seulement les documents ajoutés après l’envoi et non vérifiés ; un document refusé se « remplace » par un nouveau, l’ancien reste visible (barré) pour l’expert** (recommandé) ; (b) tout document non vérifié, même d’origine ; (c) aucun (ajout seulement).
4. **Visibilité par défaut** 🟢 — (a) **« Privé » par défaut pour tout** (recommandé : rien n’est partagé sans geste du vendeur) ; (b) diagnostics / DPE visibles des acquéreurs par défaut (ils sont dus à l’acquéreur) ; (c) demandé à chaque ajout.
5. **Mentions « Chiffrement de bout en bout » / « chaque ouverture est enregistrée » (spec Q14)** 🟢 — (a) **texte corrigé : « Documents chiffrés et stockés en Europe. Accès limité à vous et à l’équipe Realesty en charge du dossier. » ; « Chaque consultation par l’équipe est enregistrée » ajouté quand EPIC-12 tient le journal** (recommandé) ; (b) chiffrement côté client (empêche l’expert, l’OCR, l’IA de lire) ; (c) retirer la ligne.
6. **Sécurité du compte (spec Q16, e-mail tranché : lecture seule)** 🟢 — (a) **masquer Face ID, 2FA, mot de passe, Apple / Google ; afficher « Lien de connexion par e-mail »** (recommandé) ; (b) verrou Face ID de l’app avec `local_auth` (BSD) dès maintenant ; (c) attendre la connexion Apple / Google (compte Apple payant).
7. **Langue** 🟢 — (a) lecture seule « langue de l’appareil » ; (b) **choix dans l’app (appareil / fr / en / es), mémorisé localement et dans le profil** (recommandé) ; (c) français seulement (retirer en / es).
8. **Suppression du compte (spec Q17)** 🔴 (avant K9 : irréversible) — modalité : (a) **immédiate et définitive (fichiers puis compte), journal anonyme `account_deletions`** (recommandé) ; (b) désactivation puis suppression après 30 jours (annulable ; tâche planifiée à créer) ; (c) demande traitée par l’équipe sous 30 jours (conforme App Store si initiée dans l’app, mais manuel). Et avec une vente active (EPIC-08) : (a) **refus avec « Retirez d’abord votre bien de la vente »** (recommandé) ; (b) retrait automatique puis suppression (acceptable tant que les mandats sont de test).
9. **Notifications** 🟢 — (a) **liste complète dans Compte + « Tout voir » depuis la cloche, sans réglages** (recommandé : in-app seulement) ; (b) réglages par catégorie (visites, offres, alertes de prix) masquant certaines notifications ; (c) feuille de la cloche seulement.
10. **Profil et propriétaires des dossiers** 🟢 — (a) **indépendants : modifier son profil ne change aucun dossier (les dossiers envoyés sont verrouillés)** (recommandé) ; (b) le profil met à jour le propriétaire n° 1 des brouillons ; (c) le propriétaire n° 1 devient une vue du profil (migration plus lourde).
11. **« Profil actif » Vendeur / Acquéreur (spec Q15)** 🟢 — (a) **masqué tant que le côté acquéreur n’existe pas** (recommandé) ; (b) bascule de `profiles.role` dès maintenant (mène à l’espace acquéreur vide) ; (c) barre d’onglets combinée plus tard.
12. **Télécharger un document** 🟢 — (a) **feuille de partage iOS (`share_plus`, BSD-3, nouvelle dépendance) avec le fichier téléchargé** (recommandé) ; (b) ouvrir l’URL signée dans Safari (enregistrer depuis Safari) ; (c) aperçu seulement.
13. **Rubrique Facturation et lignes Paiements / Factures** 🟢 — (a) **masquées en v1** (recommandé : aucun paiement) ; (b) affichées vides « Aucune facture » ; (c) factures saisies par l’équipe (table `invoices`) pour les options commandées hors app.
14. **Adresse postale** 🟢 — (a) **texte libre** (recommandé) ; (b) recherche d’adresse Géoplateforme (comme V2) avec champs structurés.

**Bloquantes pour coder EPIC-11 : Q2, Q3 (RLS du coffre-fort), Q8 (suppression du compte).**

---

## Journal d’exécution

- 2026-10-03 : plan rédigé (aucun code), EPIC-11 créé (📋), README mis à jour.
- 2026-10-03 · K1 : migration `20261003080523_coffre_fort_compte.sql` (essai annulé + sonde RLS complète, `db push`) : nouveaux types (`dpe`, `contrat_entretien`, `assurance`, `copropriete`), `title`, `owner_ref`, `visibility` (RPC `set_document_visibility`), `added_after_submission` (trigger : tout ajout à un dossier envoyé, c.-à-d. statut ≠ `draft`), `verified_at` / `verified_by`, `rejected_reason`, `replaced_by` (RPC `replace_document`) ; politiques d’insertion / renommage / suppression (ajouts non vérifiés) pour les dossiers `in_review` / `certified`, restrictive « dossier du bien » ; Storage : ajout dans le dossier d’un bien envoyé (jamais `photos/`, pas d’écrasement), suppression des seuls fichiers sans ligne ; `notifications.kind` en contrôle de format (idempotent, identique à EPIC-08) ; `staff_verify_document` / `staff_reject_document` (+ `vault_rubric_of`, `document_kind_label`) ; `profiles` + `last_name`, `phone`, `postal_address`, `locale`, `deactivated_at`, `deletion_due_at` ; `account_deletion_blockers`, `deactivate_account`, `reactivate_account`, `account_has_active_sale` / `account_is_staff` (tables d’EPIC-08 / EPIC-12 détectées par `to_regclass`, sondées avec des tables factices) ; `account_deletions` + fonctions de purge (service role) ; `pg_net` + `pg_cron` (job quotidien `purge-deactivated-accounts`). Migration `20261003081101_account_purge_fallback.sql` : la fin de purge supprime aussi l’utilisateur en SQL si l’API Auth ne le trouve pas. Migration d’EPIC-08 `20261003080551_mise_en_vente.sql` recopiée (déjà sur le projet). Runbooks : `certifier-un-dossier.md` §4 bis, nouveau `suppression-de-compte.md`.
- 2026-10-03 · K9 (serveur) : Edge Function `purge-accounts` (déployée `--no-verify-jwt`, secret partagé `PURGE_ACCOUNTS_SECRET` = Vault `purge_accounts_secret`, Vault `project_url`), tests Deno ; essai de bout en bout sur un compte de test (purge OK, utilisateur et biens supprimés, journal écrit puis nettoyé).
- 2026-10-03 · K2 : dépôts — `profile_repository` (`Profile` étendu, `ProfileDetails`, `updateDetails`, `updateLocale`, `getDeletionBlockers`, `deactivateAccount`, `reactivateAccount`), `auth_repository.signOut(everywhere:)`, `sale_repository` (pagination `before`, `markAllRead`, types `document_rejected` / `document_verified`), `property_repository` (`PropertyDocument` étendu, `DocumentVisibility`, `getDocumentsOf`, `renameDocument`, `setDocumentVisibility`, `replaceDocument`, `downloadDocument`, `uploadDocument(title, ownerRef)`).
- 2026-10-03 · K3 : **repli du plan** (§8) — pas de déplacement du code de V7 (risque de conflit avec les branches en parallèle) : le coffre-fort réutilise en place `DocumentPicker`, `showDocumentScan`, `ScanPdfBuilder`, `ReuseDocumentSheet`, `DocumentOptionSheet`, `DocumentsCubit.mimeTypeOf`. V7 ne change que par les libellés des nouveaux types.
- 2026-10-03 · K4/K5 : `lib/seller_space/vault/` — C1 `VaultPage` (sélecteur bien / lot, recherche sans accents, rubriques, récents, manquants), V18 `VaultDocumentsPage` (`/vendeur/coffre/biens/<id>?rubrique=…`, `/vendeur/coffre/lots/<id>`), feuille détail (aperçu par URL signée 5 min, renommer, visibilité, télécharger = feuille de partage iOS via `share_plus`, remplacer, supprimer avec confirmation intégrée), ajout (bien → type → propriétaire → scan / fichiers / photothèque / autre bien) ; modèle pur `VaultContents` / `VaultRubric` ; `VaultCubit` (délais 15 s, ajout perdu retrouvé avant un nouvel essai, « Réessayer / Abandonner », dossier du bien tenu à jour dans `SellerTunnelCubits`).
- 2026-10-03 · K6/K7/K8 : C2 refait (identité → V19, propriétaires, informations personnelles, notifications avec non lues, langue, confidentialité → suppression), V19 `ProfilePage` (`/vendeur/compte/profil`), `LocaleCubit` (`lib/app/locale/`, mémorisé sur l’appareil et dans `profiles.locale`, appliqué par `MaterialApp.router(locale:)`), feuille Langue, page Notifications (`/vendeur/compte/notifications`, groupes, pages de 50, tout marquer comme lu) + « Tout voir » et 10 dernières dans la feuille de la cloche.
- 2026-10-03 · K9 (app) : `lib/account_deletion/` — `/compte/suppression` (accessible depuis tous les espaces, y compris l’espace acquéreur provisoire et sans rôle) et `/compte/desactive` (seul écran d’un compte désactivé, `appRedirect`).
- 2026-10-03 · K10 : parcours dans `app_test.dart` (coffre-fort, V18, lot, compte, V19, notifications, suppression, compte désactivé en anglais), docs, CLAUDE.md ; 100 % de couverture, analyse, bloc lint, format, licences, tests Deno ; build iOS release (development).
- 2026-10-03 · Revue (corrections) : migration `20261003093730_coffre_fort_compte_hardening.sql` (essai annulé + sonde, `db push` ; migration d’EPIC-08 `20261003093204_mise_en_vente_ajustements.sql` recopiée) — **M1** `account_purge_begin` revérifie les blocages (vente active, compte d’équipe) : le compte est sauté, le motif noté sur le profil (`purge_blocked_reason`, `purge_blocked_at`) et visible dans la vue `staff_purge_blocked_accounts` ; les comptes jamais bloqués passent en premier (`account_purge_due`). **S1** `account_purge_check` (appelée par `purge-accounts` avant de supprimer les fichiers, puis avant l’utilisateur) et `account_purge_finish` (renvoie un booléen) revérifient que le compte est toujours désactivé, échu et non bloqué : une réactivation entre deux étapes garde fichiers et compte. **S2** un compte désactivé ne peut plus rien écrire : trigger `refuse_deactivated_writes` (aide `account_is_active`) sur les biens, leurs tables filles, documents, photos, lots, réponses en attente et les tables de vente d’EPIC-08 (y compris via leurs RPC), politiques Storage restrictives (insert / update) ; la réactivation reste possible. Détails : type d’un document vérifié figé, aucun document dans un dossier `photos/`. `purge-accounts` redéployée (journaux sans identifiant, revérifications) et testée de bout en bout. App : variante `RealestyButtonVariant.destructive` (galerie) pour « Supprimer mon compte » et la confirmation de suppression d’un document ; libellés traduits des informations extraites ; V19 « Pièce d’identité » d’après la pièce de l’utilisateur ; icône Mandats = stylo (pas d’éclair dans le design system : Énergie garde l’étincelle).
- 2026-10-03 · Fusion de `main` (EPIC-08) : migration `20261003123857_account_active_sale_converge.sql` (essai annulé + sonde, `db push`) — `account_has_active_sale` délègue à `has_active_sale(owner)` d’EPIC-08 : une seule définition de la « vente active » (`mandate_signed`, `published` ; `plan_chosen` et `withdrawn` ne bloquent pas), repli sur l’ancienne requête si la fonction n’existe pas. Icônes de la cloche pour les types de notification d’EPIC-08.

## Conception de la suppression du compte (arbitrage Q8)

| Élément | Choix |
|---|---|
| Désactivation | RPC `deactivate_account()` (sans paramètre ; la saisie « SUPPRIMER », traduite, est vérifiée dans l’app) : `deactivated_at`, `deletion_due_at = +30 jours` ; idempotente ; puis `signOut(scope: global)`. |
| Connexion d’un compte désactivé | Autorisée, mais `appRedirect` n’ouvre que `/compte/desactive` (« Réactiver mon compte » / « Se déconnecter »). |
| Vente active (EPIC-08) | `account_has_active_sale(uid)` : délègue à `has_active_sale(uid)` d’EPIC-08 (`mandate_signed`, `published` ; EPIC-10 l’étendra là seulement), repli sur `sales` via `to_regclass` ; refus `active_sale` + bouton « Retirer mon bien de la vente » (→ `/vendeur`, carte « Ma vente » d’EPIC-08). Une vente en `plan_chosen` (sans mandat) ne bloque pas. |
| Équipe (EPIC-12) | `account_is_staff(uid)` via `to_regclass('public.staff_members')` ; refus `staff_account`. |
| Purge | pg_cron et pg_net sont disponibles sur le projet → job quotidien → Edge Function `purge-accounts` (fichiers de tous les buckets sous `<uid>/`, puis utilisateur Auth) ; blocages revérifiés à chaque étape (compte sauté et signalé) ; runbook pour la lancer à la main. |
| Compte désactivé | Lecture seule côté serveur (trigger `refuse_deactivated_writes`, Storage) jusqu’à la réactivation. |
| App Store 5.1.1(v) | Entrée dans l’app (Compte → Mes données, V19, espace acquéreur) ; la demande est faite dans l’app, la suppression est automatique. |

## Choix par défaut en attendant le porteur de projet

Les questions non bloquantes ont été codées avec l’option recommandée :
- Q1 : sélecteur de bien / lot en haut de C1, vue lot agrégée (le choix est gardé pour la session, pas encore sur l’appareil).
- Q4 : tout est « Privé » par défaut.
- Q5 : « Documents chiffrés et stockés en Europe. Accès limité à vous et à l’équipe Realesty en charge du dossier. » (pas de « bout en bout » ni de journal des consultations).
- Q6 : Face ID, 2FA, mot de passe, Apple / Google masqués ; « Lien de connexion par e-mail » affiché.
- Q7 : choix de la langue dans l’app (appareil / fr / en / es), mémorisé sur l’appareil et dans le profil.
- Q9 : liste complète dans Compte + « Tout voir » depuis la cloche, sans réglages.
- Q10 : profil et propriétaires des dossiers indépendants.
- Q11 : « Profil actif » masqué.
- Q12 : « Télécharger » = feuille de partage iOS (`share_plus`, BSD-3), fichier temporaire supprimé ensuite.
- Q13 : Facturation, Paiements, Factures masqués.
- Q14 : adresse postale en texte libre.
- « Ajouté après l’envoi » = ajouté quand le dossier n’est plus un brouillon (l’app verrouille un dossier dès son envoi) ; en `submitted`, la base autorise encore les modifications d’origine (inchangé), l’app non.

## Arbitrages du porteur de projet (2026-10-03) — prévalent sur le reste du plan
- Q2/Q3 : après l'envoi, **ajout libre** (marqué « Ajouté après l'envoi »), suppression uniquement des ajouts non vérifiés, un document refusé se remplace.
- Q8 : suppression du compte = **désactivation immédiate puis suppression définitive sous 30 jours** (réactivation possible pendant ce délai ; refus si une vente est active à préciser dans le plan).
