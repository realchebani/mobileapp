# EPIC-13 · Plusieurs biens par vendeur & lots de vente — étude & conception

Statut : **livré** (2026-10-02, voir le journal d’exécution ; les arbitrages en fin de document prévalent). Branche `feat/epic-13-multi-biens`.

## 0. Contexte

Demande du porteur de projet (2026-10-02) : « il faut laisser la possibilité à l’utilisateur de créer d’autres biens. Il peut être multi-propriétaire ou vendre une maison et son terrain à côté, ou encore par exemple un appartement séparé du garage. »

Arbitrages déjà pris (2026-10-02, voir [`decisions.md`](../decisions.md)) :

1. **Biens liés = « Lot de vente »** : chaque bien garde son dossier complet (audit, documents, statut, certification) ; plusieurs biens peuvent être regroupés en un lot vendu ensemble (ou ensemble / séparément) ; l’estimation et la future annonce peuvent porter sur le lot.
2. **Navigation : « Mes biens » dans l’onglet Mon bien** : liste des biens avec leur statut + « Ajouter un bien » ; avec un seul bien, on arrive directement sur son dossier comme aujourd’hui.
3. **Nouveau bien pré-rempli à partir d’un bien existant** : propriétaires (V1) et pièce d’identité (V7), modifiables ; éviter de dupliquer les fichiers si possible (à trancher : référence ou copie, confidentialité, chemins Storage).
4. **Tous les types de biens** : étendre V3 (maison, appartement, terrain, autre) avec garage / parking / box, cave / local / annexe, et éventuellement immeuble et local commercial, avec un **audit allégé adapté à chaque type**.

### Ce que fait le code aujourd’hui

- `properties` : une ligne par dossier, `owner_id`, `status` (`draft` → `submitted` → `in_review` → `certified`), `current_step` 1–8. Index unique partiel **`properties_one_draft_per_owner`** (`lock_submitted_dossiers.sql`) : au plus un brouillon par utilisateur ; un nombre quelconque de dossiers envoyés est déjà possible en base.
- `PropertyRepository.getOrCreateDossier(ownerId)` renvoie le dossier **le plus récemment modifié** (tout statut) ou crée un brouillon (conflit 23505 rattrapé). Aucune API « lister mes biens ».
- `SellerTunnelCubit` (fourni par `SellerTunnelShell` au-dessus de toutes les routes `/vendeur`) charge **un** dossier ; tous les écrans (tunnel V1–V8, V8b, V9, V9b, onglets) lisent `state.property`.
- Routes : `/vendeur` (Mon bien), `/vendeur/audit/<étape>`, `/vendeur/rapport`, `/vendeur/marche` — aucune ne porte l’identifiant du bien. Les notifications stockent `route = '/vendeur/rapport'` (écrit par `staff_certify_property`).
- Adaptations par type existantes : terrain (V4b réduit à assainissement + équipements extérieurs, pas de « Construit ? » en V3, pas de voix V4/V6), appartement (pas de niveaux / mitoyenneté / toiture). Elles sont dispersées (`technical_state.dart`, `property_context_state.dart`, `seller_tunnel_shell.dart`, `lifestyle_page.dart`, `voice_audit_page.dart`, `_shared/agent/schema.ts`, `handlers.ts`).
- Estimation (EPIC-05) : une par dossier envoyé (`market_snapshots`, `properties.ai_estimate_*`), seulement maison / appartement (`subject.ts` → `unsupported_type`), 3 calculs / 24 h par utilisateur. Les ventes DVF retenues contiennent **exactement un** logement (les dépendances de la même mutation sont tolérées et ignorées, les locaux commerciaux font écarter la vente).
- Voix (EPIC-06) : sessions par `(property_id, step)`, quotas par utilisateur ; refus du terrain côté serveur.
- Le plan V8b → V19 (§1.6, Q12) avait reporté le « sélecteur de bien » : EPIC-13 le traite.

---

## 1. Principes retenus

- **Un bien = un dossier** (inchangé) : la ligne `properties` reste l’unité d’audit, de verrouillage, de certification, de notification et (plus tard) de mandat. Aucun écran du tunnel ne mélange deux biens.
- **Le lot est une couche au-dessus** : il regroupe des biens du même vendeur pour l’estimation et la vente ; il ne porte aucune réponse d’audit.
- **L’URL désigne le bien** : `/vendeur/biens/<id>/…` (recommandé §4), le cubit n’est qu’un cache du bien ouvert.
- **Le type pilote le tunnel** via un modèle pur unique `PropertyTypeProfile` (étapes, sections, champs requis, documents, éligibilité à la voix et à l’estimation), partagé par l’app ; son équivalent serveur (`_shared/agent/schema.ts`) suit la même table (§8).
- **Rien n’est perdu** : changer de type masque les réponses non pertinentes sans les effacer ; supprimer un bien n’est possible qu’en brouillon (RLS existante).

---

## 2. Types de biens (V3)

Liste proposée (libellés français de V3, valeur stockée, correspondance DVF `type_local`) :

| Carte V3 | Valeur `property_type` | Précision demandée | DVF | Exemples |
|---|---|---|---|---|
| Maison | `maison` (existant) | — | Maison | maison, pavillon, villa, longère |
| Appartement | `appartement` (existant) | — | Appartement | appartement, studio, duplex |
| Terrain | `terrain` (existant) | `land_kind` : constructible / non constructible (jardin, agricole, bois) / je ne sais pas | (pas de `type_local` : nature de culture, « terrains à bâtir ») | terrain à côté de la maison, parcelle de jardin |
| Garage, parking ou box | `stationnement` (nouveau) | `parking_kind` : box fermé / garage / place couverte / place extérieure | Dépendance | garage séparé de l’appartement, place en sous-sol |
| Cave, cellier ou dépendance | `dependance` (nouveau) | texte libre court (`property_type_other`, ex. « grange », « atelier ») | Dépendance | cave, cellier, grange, atelier, abri |
| Local commercial ou professionnel | `local_commercial` (nouveau, **Q6**) | `commercial_use` (texte court : boutique, bureau, entrepôt…) | Local industriel, commercial ou assimilé | boutique en rez-de-chaussée, bureau |
| Immeuble entier | `immeuble` (nouveau, **Q6**) | nombre de logements (`units_count`) | plusieurs locaux dans la mutation | immeuble de rapport |
| Autre | `autre` (existant) | texte libre (existant) | — | mobil-home, péniche, moulin… |

Grille V3 : 8 cartes (2 colonnes × 4) avec les icônes existantes (`home`, `building`, `land`, `grid`) et 3–4 icônes à ajouter au design system (voiture / garage, carton / cave, vitrine, immeuble). Les maquettes Claude Design n’ont que 4 cartes : la grille est construite avec `SelectableCardGrid` ; demander une mise à jour du canevas (V3) en parallèle.

Recommandation : livrer en v1 de l’epic **maison, appartement, terrain, stationnement, dépendance, autre** ; `local_commercial` et `immeuble` derrière Q6 (audit « expert seulement » proposé).

---

## 3. Modèle de données (nouvelle migration `*_multi_biens.sql`)

### 3.1 Plusieurs brouillons

```sql
drop index public.properties_one_draft_per_owner;
```

La garantie « pas de double brouillon sur double tap » passe côté client : **l’app génère l’`id` (UUID) du nouveau bien** et fait un `insert` ; un nouvel essai après une réponse perdue renvoie 23505 sur la clé primaire → relire ce bien (même schéma que les lignes enfants). Le `grant insert` de `properties` est élargi à `id`, `property_type`, `property_type_other`, `lot_id`.

Garde-fou contre les abus : **au plus 10 brouillons par utilisateur** (trigger `before insert` qui compte, erreur `P0001`) — **Q11**.

### 3.2 Types et champs propres aux nouveaux types

```sql
alter table public.properties
  drop constraint properties_property_type_check,
  add constraint properties_property_type_check check (property_type in (
    'maison', 'appartement', 'terrain', 'stationnement', 'dependance',
    'local_commercial', 'immeuble', 'autre')),
  add column parking_kind text check (parking_kind in (
    'box', 'garage', 'place_couverte', 'place_exterieure')),
  add column land_kind text check (land_kind in (
    'constructible', 'non_constructible', 'inconnu')),
  add column usable_area_m2 numeric(7, 2) check (usable_area_m2 > 0),
  add column parking_features text[] not null default '{}'
    check (parking_features <@ array[
      'porte_motorisee', 'electricite', 'borne_recharge', 'eau', 'acces_securise'
    ]::text[]),
  add column units_count smallint check (units_count between 2 and 500),
  add column commercial_use text check (char_length(commercial_use) <= 100);
```

- `usable_area_m2` (« surface utile ») sert aux biens **non habitables** (stationnement, dépendance, local commercial) : on ne détourne pas `living_area_m2`, qui garde son sens légal (surface habitable, utilisée par l’estimation).
- Le nom exact de la contrainte existante est vérifié avant écriture (`\d public.properties`), la migration le nomme explicitement.
- Grants `update` ajoutés pour les nouvelles colonnes.

### 3.3 Lots de vente

```sql
create table public.property_lots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text check (char_length(name) between 1 and 80),
  -- 'ensemble': sold only together; 'ensemble_ou_separe': together, or
  -- each property on its own (Q3).
  sale_mode text not null default 'ensemble'
    check (sale_mode in ('ensemble', 'ensemble_ou_separe')),
  main_property_id uuid references public.properties (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.properties
  add column lot_id uuid references public.property_lots (id) on delete set null;
create index properties_lot_id_idx on public.properties (lot_id);
```

Choix : **appartenance = colonne `properties.lot_id`** (un bien est dans au plus un lot) plutôt qu’une table de liaison : plus simple à lire, RLS et verrou réutilisent les politiques de `properties`. Une table `property_lot_members` ne se justifierait que si un bien pouvait appartenir à plusieurs lots (scénarios de vente alternatifs) — non demandé.

Règles (triggers `security definer` avec `search_path = ''`) :

- **même propriétaire** : `properties.lot_id` ne peut pointer que vers un lot du même `owner_id` ; `main_property_id` doit être membre du lot ;
- **lot figé** dès qu’un membre est `in_review` ou `certified` : plus d’ajout / retrait de membre ni de changement de `sale_mode` (l’expert évalue un lot stable). Le retrait passe par `update properties set lot_id = null`, déjà couvert par la politique « open properties » pour le bien retiré ; le trigger vérifie en plus les autres membres ;
- un lot sans membre est supprimé par l’app (pas de trigger de nettoyage : simple et testable) ; un lot à un seul membre est autorisé transitoirement (création puis ajout).

RLS `property_lots` : select / insert / update / delete pour `owner_id = auth.uid()` ; update et delete refusés si un membre est `in_review` / `certified` (sous-requête `exists`). Grants colonne par colonne (`name`, `sale_mode`, `main_property_id`).

### 3.4 Pré-remplissage : propriétaires et pièce d’identité

**Propriétaires (V1) — copie des lignes** (recommandé) : `property_owners` reste par dossier (les co-indivisaires diffèrent souvent d’un bien à l’autre : maison du couple, terrain hérité en indivision avec un frère). L’app propose « Reprendre les propriétaires de *Maison · 12 rue des Lilas* » ; un tap copie les lignes (nouveaux UUID, `profile_id` conservé pour la position 1 = l’utilisateur), toutes modifiables ensuite. `ownership_type` est copié aussi. Pas de table « personnes » partagée : elle compliquerait le verrou (modifier un co-propriétaire d’un dossier certifié) pour un gain faible (quelques champs texte).

**Pièce d’identité (V7) — copie serveur du fichier** (recommandé, **Q1**) :

- `storage.from('property-documents').copy(<uid>/<bien A>/<fichier>, <uid>/<bien B>/<horodatage>_<nom>)` : copie interne au bucket, **aucun ré-envoi depuis le téléphone** ; puis insertion d’une ligne `property_documents` (`kind = piece_identite`, `storage_path` du nouveau fichier).
- Les politiques Storage existantes suffisent : lecture du dossier source (même utilisateur), écriture sous `<uid>/<bien B>/` permise tant que B est `draft` / `submitted`.
- Avantages : chaque dossier reste autonome (verrou, rejet par l’expert, suppression, futur partage avec un notaire ou une agence) ; aucun changement de RLS ; `storage_path unique` respecté. Coût : quelques Mo dupliqués par bien, négligeable.
- Alternative « référence » (deux lignes pointant le même objet) : casse l’unicité de `storage_path`, la suppression d’un document effacerait le fichier de l’autre dossier, et le verrou Storage (2ᵉ segment = bien) ne correspond plus. Écartée.
- Alternative « coffre-fort personnel » (`user_documents` sous `<uid>/identite/…` + liens par bien) : c’est la cible naturelle du Coffre-fort C1 (EPIC-11) ; à reprendre alors, la copie d’aujourd’hui restant compatible (migration possible par empreinte SHA-256).
- Le titre de propriété **n’est pas** proposé par défaut : un acte peut couvrir plusieurs biens (maison + garage achetés ensemble) → option « Réutiliser un document d’un autre bien » dans la feuille de fichiers de V7, pour tout type de document (même mécanisme de copie) — à confirmer (Q1).

Confidentialité : les fichiers restent dans le dossier privé de l’utilisateur ; aucune donnée ne passe d’un utilisateur à un autre ; la copie est tracée par `property_documents.extracted = null` et un `file_name` identique (pas de nouvelle colonne). Si l’on veut tracer la source : colonne `copied_from uuid` facultative (proposée, non bloquante).

**Adresse (V2) — suggestion** (bonus, **Q10**) : « Même adresse que *Maison · 12 rue des Lilas* » pré-remplit l’adresse BAN et propose les parcelles voisines ; les parcelles restent à confirmer (un garage peut être sur une autre parcelle).

### 3.5 Notifications et fonctions `staff_*`

- `notifications.route` : les nouvelles lignes portent `/vendeur/biens/<property_id>/rapport` ; la migration réécrit les lignes existantes (`update … set route = '/vendeur/biens/' || property_id || '/rapport' where route = '/vendeur/rapport'`) ; `staff_start_review` et `staff_certify_property` sont recréées (`create or replace`) avec la nouvelle route.
- `valuations` reste par bien. Un avis de valeur de lot (Q8) ajouterait `valuations.lot_id` plus tard.

### 3.6 RLS : récapitulatif

| Objet | Lecture | Écriture |
|---|---|---|
| `properties` | propriétaire | inchangé (`draft` / `submitted`) ; insert : `status = draft`, ≤ 10 brouillons |
| `properties.lot_id` | — | bien ouvert + lot du même propriétaire + lot non figé (trigger) |
| `property_lots` | propriétaire | propriétaire, si aucun membre `in_review` / `certified` |
| enfants, documents, Storage | inchangé | inchangé (la copie d’identité passe par les politiques existantes) |
| `notifications`, `valuations`, `market_snapshots` | inchangé | inchangé |

Sonde RLS : bloc `DO` annulé (`supabase db query --linked`) couvrant deux brouillons, lot croisé entre deux utilisateurs (refusé), lot figé après `staff_start_review`, copie Storage vers un bien verrouillé (refusée).

---

## 4. Routage

### 4.1 Options

| | (A) Identifiant dans l’URL `/vendeur/biens/:propertyId/…` — **recommandé** | (B) Bien sélectionné dans l’état, routes inchangées |
|---|---|---|
| Liens profonds, notifications | la route désigne le bien sans ambiguïté | il faut un paramètre `?bien=` ou une sélection implicite |
| Retour arrière, onglets | chaque pile garde son bien | la sélection globale peut changer sous une pile ouverte |
| Coût | chemins des étapes à paramétrer (centralisé dans `SellerTunnelStep` + `SellerTunnelNavigation`) | faible au départ, dettes ensuite (V10–V19 sont par bien) |

### 4.2 Cible (A)

```
/vendeur                                   Mon bien : 1 bien → son dossier (comme aujourd’hui) ; ≥ 2 → « Mes biens »
/vendeur/biens/nouveau                     Ajouter un bien (feuille plein écran : type, pré-remplissage, lot)
/vendeur/biens/:propertyId                 accueil du bien (SellerHomePage brouillon / V9 envoyé)
/vendeur/biens/:propertyId/rapport         V9b
/vendeur/biens/:propertyId/marche          V8b (plein écran)
/vendeur/biens/:propertyId/audit/<étape>   V1 → V8 (plein écran, sellerNavigatorKey)
/vendeur/lots/:lotId                       fiche du lot (membres, mode de vente, estimation du lot)
```

- **Un seul `SellerTunnelCubit`** reste fourni par `SellerTunnelShell` (au-dessus des onglets et des écrans plein écran, ce qui évite de dupliquer le fournisseur entre les deux navigateurs) ; il devient le **cache du bien ouvert** : `open(propertyId)` charge le bien s’il n’est pas déjà chargé. Un widget `PropertyRouteScope(propertyId)` enveloppe chaque page sous `/vendeur/biens/:propertyId` et appelle `open` ; il montre le chargement / l’erreur (logique actuelle de `SellerTunnelGate`) et `PropertyNotFoundFailure` → retour à `/vendeur`.
- Un nouveau **`SellerPropertiesCubit`** (dans le même shell) tient la liste résumée des biens et des lots (`listProperties`, `listLots`), rafraîchie après création, envoi, suppression, tirer-pour-actualiser.
- `SellerTunnelStep.path` devient un **segment** (`proprietaires`) + `location(propertyId)` ; `fromPath` lit le segment final ; `SellerTunnelNavigation` (`goToTunnelStep`, `goBackFrom`, `leaveTunnel`) lit l’identifiant du bien ouvert dans le cubit → **les écrans d’étape ne changent pas**.
- `lockRedirect(location)` compare le segment d’étape et redirige vers `/vendeur/biens/<id>/audit/envoye` ; le verrou reste **par bien** (`isLocked` = statut du bien ouvert).
- `AppRoutes` : `sellerProperty(id)`, `sellerPropertyAudit(id, step)`, `sellerReport(id)`, `sellerMarket(id)`, `sellerLot(id)`, `sellerNewProperty` ; `isRouteAvailable` adapté aux motifs paramétrés.
- **Compatibilité** : les anciennes routes `/vendeur/rapport`, `/vendeur/marche`, `/vendeur/audit/<étape>` redirigent (redirect de route) vers le bien ouvert, à défaut le seul bien, à défaut `/vendeur`. Utile pour les notifications déjà créées si la migration n’est pas encore poussée et pour les tests existants pendant la transition.
- `appRedirect` : inchangé (espace vendeur = tout ce qui commence par `/vendeur`).

---

## 5. App : cubits et espace vendeur

### 5.1 `PropertyRepository`

- `listProperties(ownerId)` → `List<PropertySummary>` (id, statut, type, adresse courte, `current_step`, `lot_id`, `ai_estimate_*`, `updated_at`), tri : brouillons récents d’abord puis envoyés.
- `createProperty({required String id, PropertyType? type, String? lotId})` (insert idempotent, 23505 → `getProperty(id)`), `deleteProperty(id)` (brouillon : supprime d’abord les fichiers Storage listés par `getDocuments`, puis la ligne ; les enfants partent en cascade).
- `copyOwners({from, to})`, `copyDocument(PropertyDocument, {toPropertyId, ownerId})` (copie Storage + insert, nettoyage du fichier si l’insert échoue).
- Lots : `listLots`, `createLot`, `updateLot`, `deleteLot`, `setPropertyLot(propertyId, lotId?)`.
- `getOrCreateDossier` est **remplacé** : au premier chargement, si l’utilisateur n’a aucun bien, l’app en crée un (comportement actuel conservé pour le premier bien).
- Modèles : `PropertyType` (+ `parking`, `outbuilding`, `commercial`, `building`), `ParkingKind`, `LandKind`, `ParkingFeature`, champs de `Property`, `PropertyLot`, `LotSaleMode`, `PropertySummary`.

### 5.2 `SellerTunnelCubit`

- Constructeur inchangé (repo, ownerId) ; `load()` → `open(String propertyId)` ; `refresh()` inchangé ; `retry()` ré-ouvre le dernier id.
- État : `property` (bien ouvert) ; `isLocked`, `resumeStep` deviennent **dépendants du type** via `PropertyTypeProfile` (§7).
- `saveAndContinue` : `next` = prochaine étape **applicable au type** (`profile.nextAfter(step)`).

### 5.3 Espace vendeur

- `MyPropertyPage` : `SellerPropertiesCubit` vide → crée le premier bien puis affiche son accueil ; **1 bien** → ouvre ce bien et montre son accueil (SellerHomePage ou V9) **inline**, comme aujourd’hui, avec en pied une carte discrète « Ajouter un bien » ; **≥ 2 biens** → `MyPropertiesPage` (« Mes biens »).
- **« Mes biens »** : en-tête `SellerSpaceHeader` (cloche), puis lots (carte de lot : nom, nombre de biens, mode de vente, estimation du lot) et biens isolés ; chaque ligne : icône du type, libellé (« Maison · 12 rue des Lilas »), badge de statut (`Brouillon · étape 3/7`, `Envoyé`, `Analyse en cours`, `Certifié`), pastille si notification non lue, glisser / menu « Supprimer » pour un brouillon (confirmation intégrée). Bouton principal « Ajouter un bien ».
- **Accueil d’un bien** (SellerHomePage / V9) : flèche retour vers « Mes biens » quand ≥ 2 biens ; mention du lot (« Fait partie du lot *Maison + terrain* ») avec lien vers la fiche du lot.
- **Ajouter un bien** (`/vendeur/biens/nouveau`) : 1) type (grille V3, préremplit `property_type`) ; 2) « Vendu avec un autre bien ? » → non / avec *Bien X* (crée ou rejoint un lot) ; 3) « Reprendre mes informations de *Bien X* ? » (propriétaires + pièce d’identité, cases cochées par défaut, visible seulement si un bien existe). « Commencer l’audit » ouvre V1 du nouveau bien, déjà rempli si choisi (V1 affiche la provenance « Repris de *Bien X* »).
- **Fiche du lot** : membres (ajouter / retirer tant que le lot n’est pas figé), mode de vente, bien principal, estimation du lot (§6), « Dissoudre le lot ».
- **Notifications** : la feuille liste toutes les notifications, chaque ligne préfixée par le libellé court du bien ; la route ouvre le bon bien ; pastilles par bien dans « Mes biens » ; le point de l’onglet Mon bien reste global.
- `ValuationCubit` : chargé pour le bien ouvert (déjà par `propertyId`) ; recharger quand le bien ouvert change.

Maquettes : « Mes biens », « Ajouter un bien », fiche du lot et nouvelle grille V3 n’existent pas dans le canevas ; elles sont construites avec les composants du design system (`ActionCard`, `SelectableCard`, `RealestyBadge`, `KeyValueRow`) et soumises au porteur de projet sur iPhone ; demander leur ajout au canevas.

---

## 6. Estimation (EPIC-05) par bien et par lot

**Par bien : inchangé.** Éligibles : maison, appartement (`subject.ts`). Les autres types reçoivent `unsupported_type` → V8 / V9 affichent déjà « l’expert vous donnera directement son avis de valeur » ; le libellé est adapté par type (« Pour un garage, l’expert s’appuie sur les ventes de places du quartier »).

**Par lot — options :**

| | Principe | Pour | Contre |
|---|---|---|---|
| (a) **Somme des estimations des membres** — recommandé | fourchette du lot = somme des bas / médianes / hauts, calculée **dans l’app** (aucun nouveau calcul serveur) ; affichée seulement si **tous** les membres estimables le sont, avec la liste des biens « estimés par l’expert » sinon | simple, transparent, aucun coût | une maison + garage séparés s’additionnent seulement si le garage a une estimation (jamais en v1) → le lot montre « Maison : 310–350 k€ · Garage : par l’expert » |
| (b) Estimation du logement principal seulement | le lot reprend l’estimation du bien principal, annotée « dépendances non comprises » | lisible | sous-estime le lot |
| (c) Nouveau calcul serveur sur des mutations DVF de même composition (logement + dépendance) | comparables « maison + garage » | fidèle | trop peu de ventes, double comptage (les ventes de maisons incluent déjà souvent leurs dépendances), gros chantier |

Recommandation : **(a)** en v1, et un **lot n’ajoute pas de calcul** (pas d’impact sur le quota de 3 / 24 h). Extension EPIC-05 possible ensuite (**Q5**) : estimation des **stationnements** (mutations DVF ne contenant que des Dépendances, une seule, médiane du prix par unité dans le rayon) et des **terrains à bâtir** (nature de culture « terrains à bâtir », €/m²) ; ces deux calculs rendraient (a) complet pour les cas cités par le porteur de projet.

Point d’attention documenté dans V8b : les ventes de maisons comparables incluent souvent garage et dépendances sur la même parcelle ; additionner un garage **voisin** reste juste, additionner un garage **sur la même parcelle** que la maison compterait deux fois → l’app n’additionne pas un membre `stationnement` / `dependance` dont une parcelle est commune avec le bien principal (message « compris dans l’estimation de la maison »).

Certification : l’expert certifie chaque bien (inchangé) ; valeur de lot certifiée → **Q8**.

---

## 7. Adaptation du tunnel par type

Un modèle pur `PropertyTypeProfile.of(PropertyType?)` (dans `lib/seller_tunnel/models/`) remplace les tests `propertyType == …` dispersés : étapes applicables, sections V4b, champs requis, documents, voix, estimation. Le numéro stocké dans `current_step` reste 1–8 (les étapes sautées sont simplement passées) ; l’en-tête affiche « k/n » selon les étapes du type ; `resumeAt` prend la première étape applicable ≥ `current_step`.

Légende : ✅ complet · ◐ allégé · — sauté.

| Étape | Maison | Appartement | Terrain | Stationnement | Dépendance | Local commercial (Q6) | Immeuble (Q6) | Autre |
|---|---|---|---|---|---|---|---|---|
| V1 Propriétaires | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (+ « Société ? » plus tard) | ✅ | ✅ |
| V2 Adresse & cadastre | ✅ | ✅ (parcelle de l’immeuble) | ✅ (plusieurs parcelles) | ✅ (parcelle de la résidence) | ✅ | ✅ | ✅ | ✅ |
| V3 Contexte | ✅ | ✅ | ◐ sans « Construit ? », + `land_kind` | ◐ `parking_kind`, sans « Construit ? » | ◐ précision, « Construit ? » | ◐ `commercial_use` | ◐ `units_count` | ✅ |
| V4 Audit vocal | ✅ | ✅ | — | — | — | — | — | ✅ |
| V4b Audit technique | ✅ toutes sections | ◐ sans niveaux / mitoyenneté / toiture | ◐ assainissement + équipements ext. (existant) | ◐ **nouvelle section** : surface utile (facultative), `parking_features`, niveau (sous-sol / RDC / extérieur) | ◐ surface utile, année de construction (facultative), électricité / eau | ◐ surface utile (requise), année, chauffage (facultatif) | ◐ année, matériaux, toiture, chauffage | ✅ chauffage facultatif (existant) |
| V5 / V5c Pièces | ✅ | ✅ | — | — | — | — (surface en V4b) | — (expert) | ◐ facultatif (« Passer ») |
| V6 Cadre de vie | ✅ | ✅ | ✅ sans voix (existant) | — | — | ◐ atouts / points de vigilance, sans bruit ni vis-à-vis | ✅ | ✅ |
| V7 requis pour l’envoi | titre + identité | titre + identité | titre + identité | titre + identité | titre + identité | titre + identité | titre + identité | titre + identité |
| V7 listés (facultatifs) | taxe foncière, énergie, travaux, diagnostics, SPANC selon assainissement | idem (+ PV d’AG / règlement de copro. en « autre ») | taxe foncière, SPANC selon assainissement, plan / bornage (« autre ») | taxe foncière, règlement de copro. (« autre ») | taxe foncière, plan | taxe foncière, diagnostics (DPE tertiaire), bail en cours (« autre ») | taxe foncière, diagnostics, baux | comme aujourd’hui |
| Score de transparence | réponses actuelles | idem | adresse, parcelle, type, achat, assainissement | adresse, parcelle, type, achat, `parking_kind` | adresse, parcelle, type, achat, surface utile | adresse, parcelle, type, achat, surface, année | adresse, parcelle, type, achat, année | actuel |
| Estimation (EPIC-05) | ✅ DVF Maison | ✅ DVF Appartement | — expert (Q5) | — expert (Q5 : DVF Dépendance) | — expert | — expert | — expert | — expert |

Notes :

- Changer de type en V3 tant que le bien est brouillon : les réponses devenues hors sujet sont **masquées et ignorées** (score, estimation, envoi), pas effacées (**Q9**).
- La taxe foncière reste « requise » dans le score (non bloquante) pour tous les types, comme aujourd’hui.
- Les types sautant V5 et V6 vont directement de V4b à V7 : `SellerTunnelStep.next` devient `profile.nextAfter(step)`.

---

## 8. Voix et agent IA (EPIC-06)

- Sessions et quotas : déjà par bien (`agent_sessions.property_id`) et par utilisateur (`agent_turns.owner_id`) → **aucun changement de schéma** ; le quota quotidien par utilisateur couvre tous ses biens (voulu : coût maîtrisé).
- `_shared/agent/schema.ts` : `PropertyType` étendu ; `requiredFor` et la règle « bâtiment / bâtiment entier » alignés sur la table §7 ; les nouveaux types non vocaux (`stationnement`, `dependance`, `local_commercial`, `immeuble`) sont refusés en `400` comme le terrain (`handlers.ts`) ; `prompt.ts` : libellés des nouveaux types. L’app masque le micro via `PropertyTypeProfile.voice` (V4 et V6).
- La migration `agent_conversations` n’est toujours pas poussée (arbitrage EPIC-06) : EPIC-13 n’en dépend pas.
- Aucun contexte inter-biens n’est donné à l’agent (un tour = un bien) : pas de fuite d’un dossier vers un autre.

---

## 9. Migration des données existantes

- Les dossiers existants restent tels quels (une ligne = un bien), `lot_id = null`, types inchangés. Aucun backfill nécessaire hors `notifications.route` (§3.5).
- Ordre : 1) pousser la migration (additive sauf la suppression de l’index et le remplacement de la contrainte de type, sans effet sur les lignes existantes) ; 2) déployer `agent-turn` / `agent-transcribe` mis à jour (acceptent les nouveaux types) ; 3) installer l’app. L’ancienne app (seule sur l’iPhone du porteur) reste fonctionnelle entre 1 et 3 : elle lit « le dossier le plus récent », ignore les colonnes nouvelles ; seule différence, `getOrCreateDossier` ne voit plus d’erreur 23505 (sans effet).
- Rollback : recréer l’index unique n’est possible que s’il n’y a qu’un brouillon par utilisateur → documenter la requête de vérification dans le journal d’exécution.

---

## 10. User stories (EPIC-13)

Détail et statuts dans [`EPIC-13-multi-biens.md`](../epics/EPIC-13-multi-biens.md).

- **US-13.1 · Mes biens** — liste, statuts, accès direct avec un seul bien.
- **US-13.2 · Ajouter un bien** — type choisi d’emblée, plusieurs brouillons, idempotence.
- **US-13.3 · Reprendre les propriétaires** — copie modifiable.
- **US-13.4 · Réutiliser la pièce d’identité** — copie serveur, sans ré-envoi.
- **US-13.5 · Tous les types de biens** — grille V3 étendue.
- **US-13.6 · Audit adapté au type** — étapes, sections, documents, score.
- **US-13.7 · Lot de vente** — regrouper, mode de vente, verrou.
- **US-13.8 · Estimation par bien et par lot** — somme, cas non estimables.
- **US-13.9 · Notifications et liens par bien** — routes paramétrées, compatibilité.
- **US-13.10 · Supprimer un brouillon** — fichiers compris.
- **US-13.11 · Voix selon le type** — agent aligné.

---

## 11. Découpage (tranches de 1 à 2 h, un agent codeur chacune)

| # | Tranche | Fichiers possédés (exclusifs) | Dépend de |
|---|---|---|---|
| M1 | **Migration** `multi_biens` : suppression de l’index, contrainte de type, nouvelles colonnes, `property_lots` + RLS + grants, `properties.lot_id` + triggers (même propriétaire, lot figé, ≤ 10 brouillons), grants insert/update, réécriture des routes de notifications, `staff_start_review` / `staff_certify_property` recréées ; `db push --dry-run` puis `db push` ; sonde RLS | `supabase/migrations/2026…_multi_biens.sql`, `docs/runbooks/certifier-un-dossier.md` (routes, lots) | — |
| M2 | **`property_repository`** : enums, champs `Property`, `PropertySummary`, `PropertyLot`, `listProperties`, `createProperty`, `deleteProperty`, `copyOwners`, `copyDocument`, lots ; retrait de `getOrCreateDossier` (gardé `@Deprecated` jusqu’à C1) ; tests 100 % | `packages/property_repository/**` | M1 (schéma figé par ce plan : peut démarrer en parallèle) |
| A1 | **Agent** : types, `requiredFor`, refus des types non vocaux, libellés du prompt ; tests ; déploiement `agent-turn` / `agent-transcribe` | `supabase/functions/_shared/agent/**`, `supabase/functions/tests/agent*` | — |
| T1 | **`PropertyTypeProfile`** (modèle pur §7 : étapes, sections, champs requis, documents, réponses du score, voix, estimation) + `SellerTunnelStep` (segments, `location(id)`, `nextAfter` délégué) ; tests | `lib/seller_tunnel/models/**` | M2 (enums) |
| C1 | **Cubits** : `SellerTunnelCubit.open(id)` / état dépendant du type, `SellerPropertiesCubit` (biens + lots) ; tests | `lib/seller_tunnel/cubit/**`, `lib/seller_space/cubit/seller_properties_*` | M2, T1 |
| R1 | **Routage** : `AppRoutes`, `app_router.dart` (`/vendeur/biens/:id/…`, `/vendeur/lots/:id`, nouveau), redirections de compatibilité, `PropertyRouteScope`, `SellerTunnelShell` / `Gate`, `SellerTunnelNavigation`, `isRouteAvailable` ; adaptation de `test/app/view/app_test.dart` (parcours V1 → V8) | `lib/app/router/**`, `lib/seller_tunnel/view/**`, `lib/seller_space/widgets/route_available.dart`, `test/app/**` | C1 |
| T2 | **V3** : grille 8 types, précisions (`land_kind`, `parking_kind`, `commercial_use`, `units_count`), icônes DS ; l10n `context*` | `lib/seller_tunnel/steps/property_context/**`, `lib/ui/icons/**` (icônes), ARB | T1 |
| T3 | **V4b allégé** : sections stationnement / dépendance / local commercial / immeuble via le profil ; l10n `technical*` | `lib/seller_tunnel/steps/technical/**` | T1, M2 |
| T4 | **V5 / V6 / V7 / score** selon le profil : saut d’étapes, micro masqué, checklist et `_answers` par type, libellés de type (`seller_space_format.dart`, `dossier_summary_sheet.dart`) ; l10n `documents*`, `lifestyle*` | `lib/seller_tunnel/steps/documents/models/**`, `…/lifestyle/**`, `…/voice_audit/**`, `…/submitted/widgets/dossier_summary_sheet.dart`, `lib/seller_space/widgets/seller_space_format.dart` | T1 |
| S1 | **Mes biens** + `MyPropertyPage` (1 bien inline / ≥ 2 liste) + suppression d’un brouillon + retour vers la liste depuis l’accueil d’un bien ; l10n `myProperties*` | `lib/seller_space/my_property/**`, `lib/seller_space/my_properties/**` (nouveau), `lib/seller_tunnel/view/seller_home_page.dart` (pied « Ajouter un bien ») | R1 |
| S2 | **Ajouter un bien** : écran `/vendeur/biens/nouveau` (type, lot, pré-remplissage), appels `createProperty`, `copyOwners`, `copyDocument` ; provenance « Repris de… » sur V1 ; l10n `newProperty*` | `lib/seller_space/new_property/**` (nouveau), `lib/seller_tunnel/steps/owners/**` (mention de provenance) | R1, M2 |
| S3 | **Réutiliser un document** dans V7 (feuille de fichiers : « Depuis un autre bien ») + suggestion « Même adresse que… » en V2 (si Q10 = oui) ; l10n `documentsReuse*`, `locationSameAs*` | `lib/seller_tunnel/steps/documents/widgets/document_files_sheet.dart`, `…/documents/cubit/**`, `…/location/**` | S2, T4 (fichiers distincts de T4 : seulement `models/**`) |
| S4 | **Lots** : fiche `/vendeur/lots/:id`, carte de lot dans Mes biens et sur l’accueil d’un bien, estimation du lot (somme, exclusions §6) ; l10n `lot*` | `lib/seller_space/lot/**` (nouveau), `lib/seller_space/dashboard/widgets/lot_card.dart` (nouveau) | S1 |
| N1 | **Notifications par bien** : libellé du bien dans la feuille, pastilles par bien, rechargement de `ValuationCubit` au changement de bien | `lib/seller_space/notifications/**`, `lib/seller_space/shell/**`, `lib/seller_space/cubit/valuation_*`, `…/notifications_*` | R1, S1 |
| D1 | **Docs & vérification** : EPIC-13, ce plan (journal), `CLAUDE.md` (routes, lots, types), spec du tunnel §4, rendu 390×844, test iPhone, sonde RLS rejouée | `docs/**`, `CLAUDE.md`, `.github/cspell.json` | toutes |

Vagues : **1** = M1, M2, A1 · **2** = T1 · **3** = C1, T2, T3, T4 · **4** = R1 · **5** = S1, S2 · **6** = S3, S4, N1 · **7** = D1.
ARB : lecture-modification-écriture JSON puis `flutter gen-l10n` immédiatement ; préfixes de clés distincts par tranche (indiqués ci-dessus). `lib/l10n/arb/*` est partagé : une seule tranche écrit à la fois dans une vague (ordre T2 → T3 → T4, puis S1 → S2).
Contrôle : chaque tranche vérifiée par un agent indépendant (tests, revue, rendu) avant commit, comme pour les epics précédents.

---

## 12. Risques

| Risque | Effet | Parade |
|---|---|---|
| Paramétrage des routes du tunnel | régressions sur V1 → V8, V8b, V9b, notifications | `SellerTunnelNavigation` seule à construire les chemins ; redirections de compatibilité ; test de parcours complet `app_test.dart` rejoué |
| Un seul `SellerTunnelCubit` partagé alors que deux onglets montrent des biens différents | un onglet affiche un autre bien après navigation | seul l’onglet Mon bien est par bien ; `PropertyRouteScope` ré-ouvre le bon bien à chaque page ; test « ouvrir A, puis B via notification, retour → A » |
| Multiplication des cas par type | logique dispersée, incohérences app / serveur | `PropertyTypeProfile` unique côté app ; table §7 recopiée dans `schema.ts` avec un test de parité (fixture JSON partagée) |
| Fichiers orphelins à la suppression d’un brouillon | stockage gaspillé, données personnelles conservées | suppression des fichiers avant la ligne ; script de contrôle des orphelins dans le runbook |
| Double comptage dans l’estimation d’un lot | fourchette trompeuse | exclusion des dépendances de la même parcelle ; mention « indicatif » ; jamais de somme partielle présentée comme totale |
| Maquettes absentes (Mes biens, lot, V3 étendu) | allers-retours de design | composants DS existants, validation sur iPhone, demande d’ajout au canevas |
| Abus (création massive de brouillons) | coûts Storage / IA | ≤ 10 brouillons (trigger), quotas IA existants par utilisateur |
| Local commercial / immeuble | droit spécifique (bail commercial, fonds de commerce, vente à la découpe) | Q6 : audit « expert seulement », ou report |

---

## 13. Questions ouvertes (porteur de projet)

1. **Pièce d’identité (et autres documents) réutilisés** : (a) **copie serveur du fichier dans le dossier du nouveau bien** (proposé : dossiers autonomes, aucun ré-envoi, RLS inchangée) ; (b) référence partagée vers le même fichier (pas de doublon, mais suppression et verrou délicats) ; (c) coffre-fort personnel de l’utilisateur (pièces d’identité rangées une fois, liées aux biens) — en avance sur EPIC-11. Et : proposer aussi la réutilisation du **titre de propriété** (acte commun maison + garage) ? (proposé : oui, via « Depuis un autre bien », jamais automatiquement).
2. **Propriétaires** : (a) **copie modifiable** (proposé) ; (b) carnet de « personnes » partagé entre biens ; (c) ne reprendre que le propriétaire principal (l’utilisateur).
3. **Mode de vente d’un lot** : (a) toujours « ensemble » ; (b) **« ensemble » ou « ensemble ou séparément »** au choix du vendeur (proposé) ; (c) en plus, un prix indicatif par bien dans le lot (prépare l’annonce).
4. **Estimation du lot** : (a) **somme des estimations des biens, seulement quand chaque bien estimable l’est** (proposé) ; (b) estimation du bien principal seulement ; (c) laisser l’expert estimer le lot.
5. **Estimer garages et terrains** (extension EPIC-05) : (a) pas en v1, l’expert s’en charge (proposé pour EPIC-13) ; (b) stationnement : médiane DVF des ventes de dépendances seules ; (c) (b) + terrains à bâtir au m².
6. **Local commercial et immeuble entier** : (a) **proposés avec un audit allégé et une valeur « expert seulement »** (proposé pour le local, l’immeuble restant en « Autre ») ; (b) les deux proposés ; (c) aucun des deux en v1.
7. **Entrée « Ajouter un bien » quand on n’a qu’un bien** : (a) **carte discrète en bas de l’accueil du bien** (proposé) ; (b) icône « + » dans l’en-tête de Mon bien ; (c) dans l’onglet Compte.
8. **Certification d’un lot** : (a) **l’expert certifie chaque bien ; une valeur de lot facultative plus tard** (proposé) ; (b) seulement par bien ; (c) une seule certification pour le lot.
9. **Changement de type après coup** (brouillon) : (a) **permis, réponses hors sujet masquées et conservées** (proposé) ; (b) type figé après V3 ; (c) permis avec confirmation et effacement des réponses hors sujet.
10. **Suggestion « Même adresse que… » en V2** : (a) **oui, parcelles à confirmer** (proposé) ; (b) non.
11. **Nombre de biens** : (a) **10 brouillons maximum, envoyés illimités** (proposé) ; (b) aucune limite ; (c) 5 biens au total en phase de test.
12. **Lot sur des adresses différentes** (maison et terrain dans la commune voisine) : (a) **permis, avec un avertissement si les biens sont à plus de 1 km** (proposé) ; (b) même commune seulement ; (c) sans contrôle.

---

## Journal d’exécution

- 2026-10-02 : plan rédigé (aucun code), EPIC-13 créé, arbitrages consignés dans `decisions.md`.
- 2026-10-02 : **M1** migrations `20261002091529_multi_biens` (index « un brouillon » supprimé, ≤ 5 biens par vendeur via trigger, 8 types, colonnes `land_kind`, `parking_kind`, `commercial_use`, `units_count`, `usable_area_m2`, `parking_level`, `parking_features`, `property_lots` + `properties.lot_id` + triggers même propriétaire / lot figé / bien principal membre, routes des notifications réécrites, `staff_*` recréées) et `20261002091600_estimate_outbuildings` (DVF « Dépendance » seule, `dvf_sources.format_version`) : essai dans une transaction annulée, dry-run, push. Sonde RLS annulée : 15 contrôles OK (deux brouillons, 6ᵉ bien refusé, lot d’un autre vendeur refusé, lot figé après `staff_start_review`, bien principal membre, suppression d’un lot).
- 2026-10-02 : **M2** `property_repository` : enums, champs, `PropertyLot`, `listProperties`, `createProperty` (id choisi par l’app, 23505 → relecture), `deleteProperty` (fichiers puis ligne, brouillon seulement), `copyOwners`, `copyDocument` (copie Storage), lots ; `getOrCreateDossier` retiré. `sale_repository` : `AppNotification.propertyId`. Couverture 100 %.
- 2026-10-02 : **A1** agent : types étendus, `VOICE_TYPES` (maison, appartement, autre), 400 pour les autres ; fixture de parité `supabase/functions/tests/fixtures/property_type_profiles.json` lue par les tests Deno et Flutter. **EPIC-05** : estimation des garages / dépendances (ventes d’une seule dépendance, médiane pondérée à l’unité, mêmes paliers rayon → période, < 5 ventes : expert ; explication sans IA). 111 tests Deno ; `estimate-property`, `agent-transcribe`, `agent-turn`, `agent-speech` redéployées.
- 2026-10-02 : **T1–T4, C1, R1, S1–S4, N1** côté app (détail dans `CLAUDE.md`). Écart au plan : au lieu d’un `SellerTunnelCubit` unique « cache du bien ouvert », un **registre** `SellerTunnelCubits` (un cubit par bien, partagé par tous les écrans de ce bien) — deux pages de biens différents ne se marchent jamais dessus ; `SellerPropertiesCubit` vit dans `lib/seller_tunnel/cubit/` (le shell en a besoin). Liste des biens = `Property` complets (≤ 5), pas de `PropertySummary`. Lot : « Regrouper en lot » depuis Mes biens et « Vendu avec… » à l’ajout. Q9 : V3/V4b n’écrivent plus que les champs du type ; `PropertyTypeProfile.clearedFrom` vide le reste à l’envoi (V7).
- 2026-10-02 : corrections après revue — migration `20261002105104_multi_biens_hardening` (sonde annulée : 9 contrôles OK ; `property_lot_is_frozen` limitée aux lots de l’appelant, `create_property_lot` crée un lot et ses biens en une transaction, trigger refusant la suppression d’un bien d’un lot figé) ; estimation : éligibilité vérifiée avant le quota (`unsupported_type` ni stocké ni compté, l’app ne demande plus d’estimation pour ces types), `estimate-property` redéployée ; candidats d’un lot = biens ouverts hors lot ; somme partielle jamais présentée comme totale ; nouveau bien visible dans Mes biens même après un échec partiel, copie de pièce d’identité sans doublon ; suppression : statut relu côté serveur, fichiers listés page par page ; V5 « Passer cette étape » pour « Autre » ; nom du lot enregistré en quittant le champ (80 caractères).
- 2026-10-02 : vérifications — 1 044 tests Flutter, couverture 100 % (lib + paquets), analyse / format / bloc lint / licences OK, build iOS release (development) OK, rendus 390 px dans le scratchpad (`epic13/screens`).

## Arbitrages du porteur de projet (2026-10-02) — prévalent sur le reste du plan
- Q1 Pièce d'identité : **copie côté serveur dans le nouveau dossier** ; le titre de propriété peut aussi être repris « Depuis un autre bien », jamais automatiquement.
- Q2 Propriétaires : **copie modifiable**.
- Q3 Lot : **« uniquement ensemble » ou « ensemble ou séparément »** au choix du vendeur.
- Q4 Estimation du lot : **somme des biens** quand tous les biens estimables en ont une (pas de double compte d'un garage sur la parcelle de la maison).
- Q5 Estimation automatique : **garages / dépendances aussi**, via la médiane DVF des ventes de dépendances seules (en plus des maisons et appartements) ; terrains non.
- Q6 **Local commercial ET immeuble entier**, chacun avec un audit adapté (valeur par l'expert).
- Q7 « Ajouter un bien » : **carte en bas de Mon bien** quand il n'y a qu'un bien.
- Q8 Certification : **chaque bien**, valeur de lot éventuelle plus tard.
- Q9 Changement de type d'un brouillon : **réponses hors sujet masquées mais conservées** (vidées à l'envoi).
- Q10 V2 : suggestion **« Même adresse que… »**, parcelles à confirmer.
- Q11 Limite : **5 biens au total par vendeur pendant la phase de test**.
- Q12 Lot à des adresses différentes : **aucun contrôle**.
