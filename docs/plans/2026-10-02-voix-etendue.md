# EPIC-14 · Voix étendue à tout le tunnel vendeur — étude & conception

Statut : **implémenté** (tranches V0–V7, V9–V16 ; V8 « banc enregistré sur l’iPhone » reste à faire), avec les **choix par défaut** du §14 en attendant les arbitrages du porteur de projet (questions §12). Branche `feat/epic-14-voix-etendue`, après la fusion d’EPIC-13 (multi-biens) : ce plan s’appuie sur ses types de biens, son `PropertyTypeProfile`, ses colonnes (`usable_area_m2`, `parking_level`, `parking_features`, `land_kind`, `parking_kind`, `commercial_use`, `units_count`) et ses routes `/vendeur/biens/:id/audit/<étape>`.

## 0. Contexte

Demande du porteur de projet (2026-10-02) : « le vocal avec l’agent IA doit pouvoir permettre de renseigner un maximum de champs dans ce tunnel — par exemple l’utilisateur doit pouvoir dicter les descriptions des pièces et éviter la saisie manuelle. »

Point de départ (EPIC-06, construit) :

- Chaîne **STT → agent → TTS** en trois Edge Functions (`agent-transcribe`, `agent-turn`, `agent-speech`), modèles les moins chers par défaut (Whisper Large v3 Turbo, **Gemini 3.5 Flash-Lite**, Kokoro `ff_siwis`), changeables par secrets (`_shared/agent/config.ts`).
- Deux étapes seulement : `technical` (V4 audit vocal Night → données de V4b) et `lifestyle` (V6 « Parlez librement »). `agent_sessions.step` est contraint à ces deux valeurs.
- Garde-fous : schéma JSON strict, **liste blanche** de champs et de codes, **citation littérale** vérifiée (`quoteFound`), confiance ≥ 0,7 sinon pastille « … ? », règles croisées (toiture ≥ construction, chambres ≤ pièces, séjour ≤ surface), **les fonctions n’écrivent jamais le dossier** (l’app écrit, RLS + verrou), quotas atomiques (120 tours et 20 min d’audio par jour et par utilisateur, 60 s par tour), consentement v2, aucune donnée d’identité envoyée aux modèles.
- App : `VoiceConversationCubit` (boucle écoute → transcription → tour → application → voix), `AgentActionBar(onMicPressed:)`, feuille Night de V6 (`lifestyle_voice_sheet.dart`), provenance des valeurs dites = **Déclaré**, `lifestyle_items.source = 'voice'`.
- EPIC-13 (en cours) : 8 types (`maison`, `appartement`, `terrain`, `stationnement`, `dependance`, `local_commercial`, `immeuble`, `autre`) ; `PropertyTypeProfile.voice` = vrai seulement pour maison / appartement / autre, et `handlers.ts` refuse les autres types (`isVoiceType`, fixture de parité `tests/fixtures/property_type_profiles.json`).

Ce qu’EPIC-14 change : **un micro sur chaque étape** (feuille vocale propre à l’étape), une **dictée de pièces** en V5c (avec une description libre par pièce), plusieurs champs dans une même phrase, des **corrections à la voix**, et une ouverture de la voix par étape plutôt que par type de bien.

---

## 1. Principes retenus

1. **Même agent, un schéma par étape.** `agent-turn` reçoit `step` ∈ {`owners`, `location`, `context`, `technical`, `rooms`, `lifestyle`} ; chaque étape déclare ses champs, ses entités (pièces, estimations, co-propriétaires), sa section de consignes et ses règles. Rien d’autre ne change dans la chaîne.
2. **L’IA propose, le serveur valide, l’app écrit** (inchangé). Les valeurs dictées vont dans le **brouillon de l’écran** (le cubit de l’étape), en surbrillance « Dicté », et ne sont enregistrées qu’au « Continuer » de l’étape, comme sur V6. Le vendeur voit toujours le formulaire.
3. **Jamais de valeur sans preuve** : chaque valeur garde une citation littérale ; en plus, une **ancre lexicale** (§4.2) : un nombre doit figurer dans sa citation, un code doit y avoir un mot-clé.
4. **Confirmer ce qui est risqué, annuler tout le reste** : application immédiate + « Annuler » par pastille et par tour ; « Est-ce correct ? » seulement pour les changements structurants (§5.3).
5. **Pas de voix là où elle ne vaut rien** : pièces jointes (V7), sélection sur carte (parcelles), coordonnées des personnes (téléphone, e-mail).
6. **La voix suit l’étape, pas le type** : la feuille vocale est proposée sur toute étape qui a des champs dictables pour le type (`PropertyTypeProfile.voiceSteps`, §6.4) ; l’audit Night V4 reste réservé aux logements.

---

## 2. Inventaire de tous les champs du tunnel

Légende des types (EPIC-13) : **M** maison · **A** appartement · **T** terrain · **S** stationnement · **D** dépendance · **L** local commercial · **I** immeuble · **Au** autre. Voix : ✅ dictable · ◐ dictable avec confirmation obligatoire ou dictée simple (STT seul) · ❌ non dictable.

### 2.1 V1 · Propriétaires (`owners`) — tous types

| Champ | Colonne / table | Voix | Pourquoi / forme | Validation | Confirmation |
|---|---|---|---|---|---|
| Unique / plusieurs propriétaires | `properties.ownership_type` (`single`, `multiple`) | ✅ | « nous sommes trois en indivision » | code ; ancre : « seul », « unique », « plusieurs », « indivision », « couple », « mon mari / ma femme »… | non |
| Propriétaire 1 : prénom, nom, téléphone, e-mail | `property_owners` position 1 | ❌ | prérempli depuis le profil et l’e-mail de connexion ; identité | — | — |
| Co-propriétaire : prénom, nom | `property_owners` (position ≥ 2) | ◐ (Q1) | « avec mon frère Marc Durand » → fiche co-propriétaire **à compléter** | 1–100 car. chacun ; citation ; pas de chiffres ; au plus 10 | **toujours** : carte « Marc Durand ? Oui / Corriger » (orthographe des noms propres peu fiable en STT) |
| Co-propriétaire : téléphone, e-mail | `property_owners.phone`, `.email` | ❌ | STT peu fiable sur e-mails et numéros, donnée de contact : saisie à l’écran (la fiche reste en erreur « à compléter ») | — | — |

Données d’identité : V1 est la seule étape où l’agent reçoit des noms propres (Q1). Le prompt de l’étape `owners` n’envoie **aucune** valeur connue (ni nom du vendeur ni co-propriétaires existants, seulement leur nombre), et le transcript de ce tour est **effacé du journal** une fois le tour traité (§7.3).

### 2.2 V2 · Adresse, cadastre, situations (`location`) — tous types

| Champ | Colonne | Voix | Pourquoi / forme | Validation | Confirmation |
|---|---|---|---|---|---|
| Adresse du bien | `address_*`, `lat`, `lng`, `address_ban_id` | ◐ **dictée simple** (Q2) | STT seulement (`agent-transcribe`, pas d’agent : l’adresse n’est pas envoyée au modèle de langage) ; le texte va dans le champ « Adresse du bien », la Géoplateforme propose ses suggestions, **le vendeur touche la bonne** (géocodage obligatoire, comme à l’écran) | celles de l’écran (résultat BAN choisi) | le choix de la suggestion |
| Me géolocaliser | (action) | ❌ | bouton GPS | — | — |
| Parcelle(s) | `property_parcels`, `parcel_confirmed` | ❌ | sélection sur la carte, confirmation « Oui, c’est correct » : le vendeur doit voir les limites | — | — |
| Situations particulières | `special_situations` (`servitude_passage`, `servitude_reseaux`, `autre`, `aucune`) | ✅ | « il y a une servitude de passage pour le voisin » | codes ; `aucune` exclusif (une nouvelle situation retire `aucune`, « aucune » vide les autres) ; ancres : « passage », « réseau », « canalisation », « ligne électrique », « aucune servitude »… | « aucune » qui efface une situation déjà cochée : confirmation |
| Précision « Autre » | `special_situation_other` | ✅ | texte libre court | ≤ 120 car. (borne de l’écran, à reprendre du code), règle de couverture du texte (§4.2) | non |
| « Même adresse que… » (EPIC-13) | — | ❌ | carte de suggestion à toucher | — | — |

### 2.3 V3 · Contexte (`context`) — selon le type

| Champ | Colonne | Types | Voix | Validation | Confirmation |
|---|---|---|---|---|---|
| Type de bien | `property_type` (8 codes) | tous | ✅ | code ; ancres (« maison », « pavillon », « appartement », « studio », « terrain », « garage », « box », « parking », « cave », « grange », « boutique », « bureau », « immeuble »…) | **oui si un type est déjà choisi** (le type change les étapes) ; non sinon |
| Précision « Autre » / dépendance | `property_type_other` | D, Au | ✅ | ≤ 100 car., couverture | non |
| Nature du terrain | `land_kind` (`constructible`, `non_constructible`, `inconnu`) | T | ✅ | code ; « je ne sais pas » → `inconnu` seulement si dit | non |
| Type de stationnement | `parking_kind` (`box`, `garage`, `place_couverte`, `place_exterieure`) | S | ✅ | code + ancre | non |
| Usage du local | `commercial_use` | L | ✅ | ≤ 100 car., couverture | non |
| Nombre de logements | `units_count` | I | ✅ | entier 2…500, nombre dans la citation | non |
| Année d’achat | `purchase_year` | tous | ✅ | 1900…année en cours, 4 chiffres dans la citation (« en 2012 », « deux mille douze ») | non |
| Prix d’achat | `purchase_price_eur` | tous | ✅ | 1 000…100 000 000 € ; « 320 000 », « trois cent vingt mille », « 320 k » ; nombre dans la citation | non |
| Construit par vous ? | `self_built` (booléen) | M, A, D, Au | ✅ | booléen ; ancre « construit », « fait construire », « bâti » | non |
| Raison de la vente | `sale_reason` (5 codes) | tous | ✅ | code + ancre (« mutation », « muté », « plus grand », « séparation », « divorce », « investissement »…) | non |
| Déjà estimé ? | `previously_estimated` | tous | ✅ | booléen ; vrai implicite si une estimation est dictée | non |
| Estimation précédente : prix, mois, agence | `previous_estimates` (`price_eur`, `estimated_month`, `agency_name`) | tous | ✅ (entité, §4.3) | prix > 0 (≤ 100 M€), mois `mm/aaaa` ≤ mois courant, agence ≤ 120 car. ; au plus 5 | non (annulable) |

### 2.4 V4 / V4b · Technique (`technical`) — selon le type (EPIC-13 `technicalFields`)

| Champ | Colonne | M | A | T | S | D | L | I | Au | Validation (inchangée sauf ✱) |
|---|---|---|---|---|---|---|---|---|---|---|
| Année de construction | `construction_year` | ✅ | ✅ | | | ✅ | ✅ | ✅ | ✅ | 1600…année en cours |
| Exposition | `orientation` (9 codes) | ✅ | ✅ | | | | | | ✅ | code |
| Surface habitable | `living_area_m2` | ✅ | ✅ | | | | | | ✅ | 5…2 000 ; ≥ séjour |
| Surface séjour | `living_room_area_m2` | ✅ | ✅ | | | | | | ✅ | ≤ habitable |
| Pièces, chambres | `rooms_count`, `bedrooms_count` | ✅ | ✅ | | | | | | ✅ | 1…30, 0…pièces |
| Niveaux | `levels` | ✅ | | | | | | | ✅ | code |
| Murs | `wall_material` | ✅ | ✅ | | | | | ✅ | ✅ | code |
| Mitoyenneté | `adjacency` | ✅ | | | | | | | ✅ | code |
| Toiture, année toiture | `roof_type`, `roof_year` | ✅ | | | | | | ✅ | ✅ | code ; ≥ construction |
| Chauffage (+ PAC : type, année) | `heating_systems`, `heat_pump_*` | ✅ | ✅ | | | | ✅ | ✅ | ✅ | liste (union) ; PAC si `pac` |
| Assainissement | `sanitation` | ✅ | ✅ | ✅ | | | | ✅ | ✅ | code |
| Équipements extérieurs (+ piscine) | `outdoor_equipment`, `pool_*` | ✅ | ✅ | ✅ | | | | | ✅ | liste ; piscine si `piscine` |
| ✱ Surface utile | `usable_area_m2` | | | | ✅ | ✅ | ✅ | | | > 0, mêmes bornes que l’écran EPIC-13 (à reprendre du code) |
| ✱ Niveau du stationnement | `parking_level` (`sous_sol`, `rdc`, `etage`, `exterieur`) | | | | ✅ | | | | | code + ancre |
| ✱ Équipements (stationnement / dépendance) | `parking_features` (5 codes ; D : `electricite`, `eau`) | | | | ✅ | ✅ | | | | liste limitée aux choix du profil |

Tout ce qui figure sur V4b est dictable : c’est déjà le cas pour l’audit V4 ; EPIC-14 ajoute les trois colonnes ✱ (types non logement) et la **feuille vocale de V4b** (sans passer par l’écran Night). L’audit V4 Night reste proposé pour M, A, Au.

### 2.5 V5 · Méthode et V5c · Pièces (`rooms`) — M, A, Au (Au facultatif)

| Champ | Colonne (`rooms`) | Voix | Forme dictée | Validation | Confirmation |
|---|---|---|---|---|---|
| Méthode de relevé | `properties.measurement_method` | ❌ (carte à toucher) | nouvelle carte V5 « **Dicter mes pièces** » → V5c avec la dictée ouverte ; stocke `manual` (Q8) | — | — |
| Nom de la pièce | `name` (1–60) | ✅ | « le séjour », « la deuxième chambre », « une buanderie » | nom normalisé sur les suggestions de l’écran (`RoomSuggestion` : Entrée, Séjour, Cuisine, Chambre n, Salle de bain, Salle d’eau, WC, Bureau, Dégagement, Cellier, Buanderie, Garage, Sous-sol, Autre) ou texte libre court couvert par la citation ; numérotation des chambres par l’app (comme l’écran) | mise en correspondance ambiguë → question (§4.3) |
| Surface | `area_m2` (0,5…500, requis) | ✅ | « 38 m² », « trente-huit mètres carrés », « 38,5 », « environ 12 » ; « 4 sur 3 » → 12 m² calculé (Q10) | bornes ; nombre (ou les deux dimensions) dans la citation ; somme des pièces habitables ≤ 2 000 | non (annulable) ; une surface remplacée sur une pièce existante s’affiche « 38 → 40 m² » |
| Niveau | `level` (`sous_sol`, `rdc`, `etage_1`, `etage_2`, `combles`) | ✅ | « au rez-de-chaussée », « à l’étage », « au deuxième », « dans les combles » | code + ancre ; **non dit → niveau par défaut de l’écran** (celui de la dernière pièce saisie), affiché, jamais déduit par l’IA | non |
| Revêtement de sol | `floor_covering` (codes de l’app : `parquet_chene`, `parquet`, `carrelage`, `moquette`, `beton_cire`, `stratifie`, `vinyle`, `autre`) | ✅ | « parquet chêne », « carrelage », « tomettes » → `autre` + le mot gardé dans la description | code + ancre | non |
| Vitrage | `glazing` (`simple`, `double`, `triple`) | ✅ | « double vitrage » | code + ancre « vitrage / fenêtres » (un « double » seul est ambigu) | non |
| Hauteur sous plafond | `ceiling_height_m` | ✅ (nouveau à l’écran : visible si renseignée) | « 2,50 m sous plafond » | 1,5…6 m, nombre dans la citation | non |
| Pièce principale / annexe | `is_main`, `is_annex` | ❌ (déduits du nom par l’app, comme à l’écran) | — | `not (is_annex and is_main)` | — |
| **Description (nouveau)** | `description` (≤ 300) | ✅ | « ouverte sur la cuisine, cheminée, baie vitrée plein sud » | règle de couverture (§4.2), ≤ 300 car., sans chiffre absent du transcript, sans téléphone ni e-mail | non (annulable, modifiable dans la fiche pièce) |
| Supprimer une pièce | (opération) | ◐ | « supprime le cellier » | pièce identifiée sans ambiguïté | **toujours** « Supprimer Cellier (4,2 m²) ? » |

À l’envoi de V5c (inchangé) : `living_area_m2` = somme des pièces habitables, `annex_area_m2` = somme des annexes.

### 2.6 V6 · Cadre de vie (`lifestyle`) — M, A, T, L (sans bruit ni vis-à-vis), I, Au

Inchangé (EPIC-06) : atouts / points de vigilance (3–140 car., 10 par liste, sans doublon), `noise_level` 1–10, `overlooking`, note secrète proposée en suggestion. EPIC-14 : ouvert au terrain et au local commercial (profil), bruit et vis-à-vis retirés du schéma pour L (`asksNeighbourhood = false`).

### 2.7 V7 · Documents — aucun champ dictable

| Élément | Voix | Pourquoi |
|---|---|---|
| Titre de propriété, taxe foncière, factures d’énergie, facture travaux, pièce d’identité, diagnostics, rapport SPANC, plan, autre (`property_documents.kind`) | ❌ | il faut un fichier (scan ou import) ; dire « j’ai mon titre » ne prouve rien |
| Type de document après un scan | ❌ (Q11) | une feuille de choix à un tap est plus rapide qu’un tour vocal |
| Commande « scanne ma taxe foncière » | option (Q11) | ouvrirait le scanner avec le type choisi ; faible valeur, non proposé en v1 |

### 2.8 Récapitulatif par type

| Étape | M | A | T | S | D | L | I | Au |
|---|---|---|---|---|---|---|---|---|
| V1 | ✅ type + co-propriétaires (Q1) | idem | idem | idem | idem | idem | idem | idem |
| V2 | ◐ adresse dictée + situations | idem | idem | idem | idem | idem | idem | idem |
| V3 | ✅ | ✅ | ✅ (+ `land_kind`) | ✅ (+ `parking_kind`) | ✅ (+ précision) | ✅ (+ usage) | ✅ (+ logements) | ✅ |
| V4 Night | ✅ | ✅ | — | — | — | — | — | ✅ |
| V4b feuille | ✅ | ✅ | ✅ (2 champs) | ✅ (3 champs) | ✅ (3 champs) | ✅ (3 champs) | ✅ (5 champs) | ✅ |
| V5c dictée | ✅ | ✅ | — | — | — | — | — | ✅ |
| V6 | ✅ | ✅ | ✅ | — | — | ✅ (listes seules) | ✅ | ✅ |
| V7 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

Champs de saisie du tunnel (hors V7, hors carte) : **≈ 90 % dictables** ; restent à l’écran : coordonnées des personnes, parcelles, choix de la suggestion d’adresse, fichiers.

---

## 3. Expérience utilisateur

### 3.1 (a) Un micro sur chaque étape → feuille vocale de l’étape

- `AgentActionBar` montre le micro sur toute étape de `profile.voiceSteps` (§6.4) quand la voix est disponible (`VOICE_ENABLED` × consentement × micro). Indice : `Répondez à la voix ou à l’écran` (existant).
- Le micro ouvre **`StepVoiceSheet`** : feuille Night compacte de V6 généralisée (orbe 95 / 64, onde, bulles du dernier échange, `J’ai fini`, `Terminer`), avec une **intro propre à l’étape** (« Dites-moi l’année et le prix d’achat, la raison de la vente, et si une agence l’a déjà estimé. ») et l’étape en cours de réponse (`next_field`).
- Sous l’échange : **pastilles « Compris »** (Lueur, une par valeur appliquée : `Achat 2012`, `Prix 320 000 €`, `Raison : mutation`) avec une croix « Annuler » chacune, **pastilles « À confirmer »** (Nuit 3 : `Type : garage ? Oui · Non`), **pastilles « … ? »** (en attente, comme V4) et un lien `Annuler ce tour`.
- Le formulaire de l’étape, derrière la feuille, se met à jour en direct ; chaque champ rempli à la voix porte l’étiquette éphémère **« Dicté »** jusqu’au « Continuer » (rien n’est enregistré avant).
- À la fermeture : instantané « 6 réponses ajoutées · Annuler » (annule toute la session de la feuille).
- Consentement : écran existant au premier usage ; **consentement v3** si Q1 = (b) (mention des noms des co-propriétaires).
- V4b garde aussi l’entrée vers l’audit Night V4 (segment ou lien « Conversation guidée ») pour M, A, Au ; le micro de V4b ouvre désormais la feuille (réponses rapides sans changer d’écran) — **Q4**.

### 3.2 (b) Dictée de pièces (V5 / V5c)

- **V5** : nouvelle carte « Dicter mes pièces » (« Décrivez chaque pièce à voix haute : nom, surface, niveau, sol, vitrage. ») → V5c, feuille de dictée ouverte. Sur V5c, le micro de la barre d’action ouvre la même feuille.
- **Feuille de dictée** (Night, hauteur ~70 %) : orbe réduit + onde ; bloc **« Pièces dictées »** : une ligne par pièce créée ou modifiée pendant la session (`Séjour · RDC · 38 m² · Parquet chêne · Double vitrage`, description en 2ᵉ ligne tronquée, étiquette `Ajoutée` / `Modifiée : 38 → 40 m²`, croix « Annuler »), total courant `82,5 m² habitables · 6 pièces`.
- **Écoute enchaînée** : après chaque tour, l’écoute reprend aussitôt ; l’agent **ne parle pas** en dictée (texte + retour haptique, Q5) : un cycle ≈ 3 s (STT 0,8 s + agent 2,5 s), sans attendre la voix.
- Exemple : « Le séjour fait 38 m² au rez-de-chaussée, parquet chêne, double vitrage, il est ouvert sur la cuisine avec une cheminée. » → `create` Séjour · RDC · 38 · parquet_chene · double · description « Ouvert sur la cuisine, avec une cheminée ».
- Plusieurs pièces dans une phrase : « À l’étage, trois chambres de 12, 11 et 10 m², toutes en parquet. » → 3 créations (Chambre 1, 2, 3 numérotées par l’app), niveau `etage_1` pour les trois (dit une fois, porte sur la liste : ancre « à l’étage » dans la citation de chacune).
- `Terminer` : l’agent récapitule **à voix haute** (« J’ai noté 9 pièces pour 115 m² habitables. Est-ce correct ? ») ; « oui » ferme, « non… » reprend la dictée. Le tableau V5c (inchangé) montre tout ; « Tout est correct, continuer » enregistre (upserts par UUID, existant).
- Fiche pièce (`room_sheet.dart`) : nouveau champ multiligne **« Description »** (facultatif, 300 car.) ; tableau V5c : la description apparaît sous le revêtement (1 ligne, tronquée).

### 3.3 (c) Plusieurs champs dans une phrase

Déjà permis par `answers[]` ; EPIC-14 l’étend aux **entités** (pièces, estimations, co-propriétaires) et garde la règle « une citation par valeur ». Les champs **conditionnels** (PAC, piscine) restent donnés au modèle même avant leur condition (`promptFields`, existant). Une phrase qui mélange plusieurs étapes (« construite en 1998, le séjour fait 38 m² ») : seule l’étape ouverte est remplie ; la réplique dit « Je noterai l’année de construction à l’étape Technique » (champs hors étape listés dans le prompt **sans** pouvoir d’écriture → `out_of_step` dans la réponse, affiché en pastille grise) — Q3 pour un mode global.

### 3.4 (d) Corrections à la voix

- « Non, plutôt 40 m² » : le prompt contient le **dernier tour** (transcript + valeurs retenues avec leur cible) et les valeurs actuelles du brouillon ; le modèle renvoie la nouvelle valeur avec `correction: true` et la même cible (champ ou pièce). Le serveur l’accepte si la citation porte le nombre ; la pastille devient `Séjour 40 m² (corrigé)`.
- « Annule » / « non, c’est faux » / « efface ça » : **traité dans l’app sans appel au modèle** (liste de formules normalisées, §5.4) → annule le dernier tour.
- « Oui » / « c’est ça » / « exact » face à une confirmation en attente : idem, local (pas de coût, pas de latence).
- Correction d’une valeur saisie à l’écran (pas dictée) : appliquée, mais signalée `Modifié : 1998 → 1999` avec annulation (jamais silencieuse).

### 3.5 Quand la voix n’est pas possible

Inchangé (EPIC-06 §3.7) : micro refusé, hors ligne, quota, 3 tours sans rien retenir → mode écran ; dossier envoyé → aucune voix (verrou). Le formulaire reste toujours utilisable sous la feuille.

---

## 4. Extraction : schémas et validation

### 4.1 Sortie du modèle (JSON Schema strict, par étape)

```json
{
  "reply_fr": "C’est noté. Au rez-de-chaussée, quelle est la pièce suivante ?",
  "answers": [
    {"field": "purchase_year", "value": "2012", "confidence": 0.95, "quote": "acheté en 2012", "correction": false}
  ],
  "entity_ops": [
    {
      "entity": "room", "op": "create", "target": "new", "copy_from": null,
      "fields": [
        {"field": "name", "value": "Séjour", "confidence": 0.95, "quote": "le séjour"},
        {"field": "area_m2", "value": "38", "confidence": 0.95, "quote": "fait 38 m²"},
        {"field": "level", "value": "rdc", "confidence": 0.9, "quote": "au rez-de-chaussée"},
        {"field": "floor_covering", "value": "parquet_chene", "confidence": 0.9, "quote": "parquet chêne"},
        {"field": "glazing", "value": "double", "confidence": 0.9, "quote": "double vitrage"},
        {"field": "description", "value": "Ouvert sur la cuisine, avec une cheminée", "confidence": 0.85, "quote": "il est ouvert sur la cuisine avec une cheminée"}
      ]
    }
  ],
  "lifestyle_items": [],
  "out_of_step": ["construction_year"],
  "next_field": "none",
  "done": false
}
```

- `field` = enum des champs de l’étape (et de l’entité) ; `value` en texte, typé par le serveur.
- `entity` ∈ {`room`, `previous_estimate`, `co_owner`} selon l’étape ; `op` ∈ {`create`, `update`, `delete`} ; `target` = `new` ou une **référence courte** fournie dans le prompt (`R1`…`R40`, `E1`…`E5`, `P2`…`P10`), jamais un UUID.
- `copy_from` (pièces, option) : « même sol que le séjour » → copie des valeurs **existantes** de la pièce citée (pas d’invention) ; citation contenant « même », « pareil », « idem ».
- Plafonds : 12 opérations d’entité par tour, `maxTokens` 2 500 pour `rooms` (1 500 ailleurs), nouvelle tentative existante sur JSON invalide.

### 4.2 Règles de validation (nouvelles, dans `validate.ts`)

| Règle | Portée | Effet en cas d’échec |
|---|---|---|
| Liste blanche champ / entité / code (existant) | tout | rejet `unknown_field` / `invalid_value` |
| Citation littérale (existant) | toute valeur | rejet `quote_not_found` |
| **Ancre numérique** : un nombre (chiffres, ou nombre écrit en français — petit analyseur « trente-huit », « deux mille douze », « trois cent vingt mille », « 320 k ») égal à la valeur doit figurer dans la citation | année, prix, surface, entier, hauteur | pastille « … ? » (`number_not_in_quote`) |
| **Ancre lexicale** : la citation contient un des synonymes du code (table par code, ex. `double` ← « double vitrage », « doubles vitrages » ; `rdc` ← « rez-de-chaussée », « en bas », « RDC ») | codes et listes | pastille « … ? » (`anchor_missing`) |
| **Couverture du texte libre** : ≥ 80 % des mots pleins de la valeur figurent dans le transcript (après normalisation), aucun nombre absent du transcript, aucun motif téléphone / e-mail, longueur max | description, précisions « Autre », usage, agence, nom libre de pièce | rejet `not_covered` |
| Bornes de l’écran (existant + nouveaux champs) | tout | `out_of_range` → « … ? » |
| Règles croisées (existant) + nouvelles : somme des pièces habitables ≤ 2 000 m² ; estimation : mois ≤ mois courant ; `aucune` exclusif ; un seul propriétaire ⇒ aucune création de co-propriétaire | selon l’étape | `inconsistent` → « … ? » |
| Champ conditionnel / non demandé pour le type (existant `isAsked`, aligné sur `PropertyTypeProfile`) | tout | `not_asked` |
| Confiance ≥ 0,7 (existant) ; **0,5–0,7 → confirmation** (au lieu d’une simple question) quand la valeur est complète | tout | `confirm` |
| **Mise en correspondance des pièces** (§4.3) | `rooms` | question ou confirmation |
| Plafonds d’entités (10 co-propriétaires, 5 estimations, 40 pièces, 12 opérations / tour) | entités | `full` |

Ces ancres s’appliquent aussi à V4 / V6. Limite connue : une erreur de transcription qui produit un nombre plausible (« Soit on a douze » au banc EPIC-06 → 12 pièces) passe les ancres, puisque le nombre est bien dans le transcript ; seules la pastille visible, l’étiquette « Dicté », la confirmation des remplacements forts et un meilleur STT (Q13) la rattrapent.

### 4.3 Mise en correspondance des pièces

Le prompt reçoit le tableau courant (envoyé par l’app, brouillon non enregistré compris) : `R1 Séjour · RDC · 38 m²`, `R2 Chambre 1 · Étage · 12,4 m²`… (sans description, ≤ 40 lignes). Le serveur contrôle chaque `update` / `delete` :

1. `target` doit exister ; la citation du nom doit **désigner** la pièce (même type normalisé : « la chambre 2 » ↔ Chambre 2 ; « la grande chambre » ↔ ambigu).
2. Plusieurs pièces du même type et aucun numéro / qualificatif → **question** (« Quelle chambre : 1, 2 ou 3 ? », pastilles touchables) ; rien n’est appliqué.
3. `create` d’un type déjà présent sans numéro (« la cuisine fait 14 m² » alors qu’une Cuisine existe) → traité comme `update` **avec confirmation** (« Modifier Cuisine : 12,8 → 14 m² ? ») plutôt qu’un doublon.
4. `delete` → **toujours** confirmation ; jamais plus d’une suppression par tour.
5. Les pièces créées dans la session sont désignables par « la dernière », « celle-ci » (référence `R*` de la dernière pièce, transmise dans l’historique).

### 4.4 Schémas par étape (registre `_shared/agent/steps/*.ts`)

| Étape | Champs (`answers`) | Entités | Colonnes lues (liste blanche) | Consignes propres |
|---|---|---|---|---|
| `owners` | `ownership_type` | `co_owner {first_name, last_name}` | `ownership_type`, nombre de co-propriétaires | noms propres tels qu’entendus ; ne jamais demander téléphone ni e-mail |
| `location` | `special_situations`, `special_situation_other` | — | ces deux colonnes | l’adresse n’est pas traitée ici (dictée simple) |
| `context` | `property_type` (+ précision selon le type), `purchase_year`, `purchase_price_eur`, `self_built`, `sale_reason`, `previously_estimated` | `previous_estimate {price_eur, month, agency_name}` | colonnes V3 + EPIC-13 | changer de type = confirmation |
| `technical` | existant + `usable_area_m2`, `parking_level`, `parking_features` | — | existant + EPIC-13 | inchangées |
| `rooms` | — | `room {name, area_m2, level, floor_covering, glazing, ceiling_height_m, description}` (+ `copy_from`) | `property_type` ; tableau envoyé par l’app | une pièce par fait, pas de déduction du niveau, description factuelle reformulée au minimum |
| `lifestyle` | existant (bruit et vis-à-vis seulement si `asksNeighbourhood`) | `lifestyle_items` (existant) | existant | inchangées |

Le **brouillon** de l’étape (valeurs non enregistrées du formulaire) est envoyé par l’app (`draft`, colonnes de la liste blanche de l’étape seulement, 4 Ko max) et sert de « valeurs connues » (prompt + règles croisées). Il ne donne aucun droit : il n’est pas écrit par le serveur.

---

## 5. Confirmation, annulation, provenance

### 5.1 Application

`AgentTurn` → `voiceTurnApplied(turn)` du **cubit de l’étape** (`OwnersCubit`, `LocationCubit`, `PropertyContextCubit`, `TechnicalCubit`, `SurfacesCubit`, `LifestyleCubit` existant), qui modifie son brouillon. V4 Night garde son écriture directe par `SellerTunnelCubit.save` (existant).

### 5.2 Annulation

Chaque cubit d’étape garde une **pile d’annulation vocale** (`VoiceEdits` : instantané du brouillon avant chaque tour + liste des champs / entités touchés). « Annuler » sur une pastille remet ce champ (ou cette pièce) à sa valeur d’avant le tour ; « Annuler ce tour » restaure l’instantané ; l’instantané de fermeture annule toute la session. Les annulations sont signalées au serveur au tour suivant (`undone_turn_ids`) pour le suivi de qualité (§7.4).

### 5.3 Quand l’agent demande « est-ce correct ? »

| Situation | Comportement |
|---|---|
| Changement de type de bien déjà choisi | confirmation (change les étapes) |
| Suppression d’une pièce, d’une estimation, d’un co-propriétaire | confirmation |
| Valeur qui **remplace** une valeur saisie à l’écran ou déjà enregistrée | appliquée + pastille « Modifié : a → b » (annulable) ; confirmation si l’écart est fort (surface ±50 %, année ±20 ans) |
| Confiance 0,5–0,7 | confirmation |
| Co-propriétaire dicté | confirmation (orthographe) |
| « Aucune » qui efface des situations | confirmation |
| Fin de dictée de pièces | récapitulatif oral + « Est-ce correct ? » |
| Tout le reste | appliqué, annulable, pas de question |

Les confirmations sont des pastilles `Oui` / `Non` touchables, et « oui » / « non » dits sont reconnus **localement** (§5.4) : une confirmation ne coûte pas de tour d’agent.

### 5.4 Reconnaissance locale (sans modèle)

Après la transcription, l’app compare le transcript normalisé à de courtes listes : `oui`, `oui c’est ça`, `c’est correct`, `exact`, `d’accord` / `non`, `non merci` / `annule`, `annuler`, `efface`, `c’est faux` / `terminé`, `c’est tout`, `j’ai fini`. Correspondance exacte (≤ 4 mots) → action locale ; sinon → `agent-turn`. Le tour transcrit est quand même journalisé (quota audio).

### 5.5 Provenance

- Valeurs dictées : **`declared`** (« Déclaré »), comme EPIC-06 — l’IA transcrit et classe, elle ne déduit rien. Écriture par `Property.mergeProvenance` (existant).
- Pièces dictées : `rooms.source = 'voice'` (**nouvelle valeur**, comme `lifestyle_items.source`) ; les mesures restent « déclarées » (pas « Mesures estimatives » du scan).
- Surface calculée à partir de dimensions dites (Q10) : `declared` aussi (calcul arithmétique de valeurs dites), pastille `4 × 3 m = 12 m²`.
- Traçabilité fine (quel tour, quelle citation) : `agent_turns.extracted` (existant). Faut-il montrer « Dicté » à l’expert ? → Q8.

---

## 6. (e) Modèle de données et serveur

### 6.1 Migration `*_voix_etendue.sql` (additive)

```sql
-- V5c · free description of a room (dictated or typed).
alter table public.rooms
  add column description text check (char_length(description) <= 300),
  drop constraint rooms_source_check,
  add constraint rooms_source_check
    check (source in ('scan', 'plan', 'manual', 'voice'));

-- Voice agent · one session per (property, step) for every voiced step.
alter table public.agent_sessions
  drop constraint agent_sessions_step_check,
  add constraint agent_sessions_step_check check (step in (
    'owners', 'location', 'context', 'technical', 'rooms', 'lifestyle'));

-- Quality follow-up: turns the seller undid (written by agent-turn with the
-- service role, like the rest of the journal).
alter table public.agent_turns
  add column undone boolean not null default false;
```

- Noms exacts des contraintes vérifiés avant écriture (`\d public.rooms`, `\d public.agent_sessions`). `rooms` a un droit de table entier : `description` est couvert ; le verrou (RLS `draft` / `submitted`) s’applique déjà.
- **Si la migration `agent_conversations` n’est toujours pas poussée** au démarrage d’EPIC-14 (arbitrage EPIC-06), la contrainte `step` est modifiée **dans** cette migration plutôt qu’après (une seule migration à pousser) — à trancher par le coordinateur avec `supabase migration list`.
- Aucune colonne ajoutée à `properties` (les colonnes EPIC-13 suffisent). Vue de suivi (§7.4) : `agent_step_stats` (lecture `service_role` seulement).

### 6.2 Edge Functions

| Fichier | Changement |
|---|---|
| `_shared/agent/schema.ts` → **registre** `_shared/agent/steps/{owners,location,context,technical,rooms,lifestyle}.ts` + `steps/index.ts` | une `StepSchema` par étape : champs (`FieldDef`), entités, colonnes lues, section de consignes, intro, schéma JSON, `isAsked` alignée sur `PropertyTypeProfile` (champs EPIC-13) |
| `_shared/agent/validate.ts` | nouveaux types de champ (`bool`, `money`, `month`, `text` avec couverture), ancres numériques et lexicales, entités, confirmations, corrections, `out_of_step` |
| `_shared/agent/french_numbers.ts` (nouveau) | analyseur des nombres écrits en français (années, prix, surfaces), testé |
| `_shared/agent/rooms.ts` (nouveau) | références `R*`, normalisation des noms, désignation, ambiguïtés |
| `_shared/agent/prompt.ts` | consignes communes (cache) + section de l’étape ; règle « identité » remplacée par une règle par étape ; historique avec les valeurs retenues et leur cible (corrections) |
| `_shared/agent/handlers.ts` | `isStep` depuis le registre ; corps `draft`, `rooms` (≤ 40), `pending_confirmations`, `undone_turn_ids` ; réponse + `entity_ops`, `confirmations`, `out_of_step` ; refus par **étape × type** (fixture de parité étendue `voice_steps`) au lieu de `isVoiceType` ; transcript effacé après le tour pour `owners` ; `maxTokens` par étape |
| `_shared/agent/config.ts` | **modèle par étape facultatif** : `OPENROUTER_MODEL_AGENT_<ÉTAPE>` (ex. `…_ROOMS`), défaut = `OPENROUTER_MODEL_AGENT` (crochet de réévaluation, §7.4) |
| `_shared/agent/db.ts` | colonnes lues par étape (liste blanche), `markUndone(ids)` |
| `agent-transcribe` | `step` du registre ; mode **dictée simple** (`mode=dictation`, V2 adresse) : transcription seule, aucune session d’agent, quota audio compté, transcript non conservé |
| `agent-speech` | inchangé (la dictée ne l’appelle pas par défaut) |
| `tests/` | tests par étape, analyseur de nombres, ancres, pièces, corrections, parité `voice_steps` |
| `supabase/bench/` | phrases nouvelles (§7.5) |

### 6.3 Quotas

Inchangés par défaut (Q9) : 120 tours et 20 min d’audio par utilisateur et par jour, 60 s par tour, transcript ≤ 2 000 car. Un tunnel complet à la voix ≈ 45–60 tours et 10–15 min d’audio (§7.1) : tient dans une journée. Les réponses « oui / non / annule » locales consomment de l’audio mais pas de tour d’agent. Ajout : **12 opérations d’entité par tour**, `draft` ≤ 4 Ko, `rooms` ≤ 40 lignes.

### 6.4 App

| Zone | Changement |
|---|---|
| `packages/property_repository` | `Room.description`, `RoomSource.voice` |
| `packages/agent_repository` | `AgentStep` étendu ; `turn(…, draft:, rooms:, pendingConfirmations:, undoneTurnIds:)` ; `AgentTurn.entityOps`, `.confirmations`, `.outOfStep` ; `transcribeOnly(audio)` (dictée simple) |
| `lib/seller_tunnel/models/property_type_profile.dart` (EPIC-13) | `voice` → `voiceSteps` (étapes à micro) + `voiceAudit` (V4 Night) |
| `lib/seller_tunnel/voice/` | `StepVoiceSheet` générique (intro, pastilles, confirmations, annulation, mode dictée), `VoiceEdits` (pile d’annulation), `LocalVoiceCommands` (§5.4), `VoiceConversationCubit` : fournisseurs `draft` / `rooms`, mode sans voix, écoute enchaînée, confirmations ; widget `DictatedTag` (« Dicté ») |
| `widgets/agent_action_bar.dart` | inchangé (le micro dépend déjà de `onMicPressed`) ; chaque page passe `onMicPressed` selon `profile.voiceSteps` |
| Étapes | `voiceTurnApplied` + marqueurs « Dicté » dans `owners`, `location` (situations + dictée d’adresse), `property_context`, `technical`, `surfaces` (dictée, description) ; `lifestyle` migre vers la feuille générique ; `method` : carte « Dicter mes pièces » |
| V8 aperçu / V9b | description des pièces affichée dans l’aperçu des données (`dossier_summary_sheet.dart`) |

---

## 7. Coûts, suivi et réévaluation

### 7.1 Coût avec les modèles actuels (Whisper Turbo + Gemini 3.5 Flash-Lite + Kokoro)

Bases mesurées (banc EPIC-06) : agent ≈ **0,0011 $ / tour** (≈ 1 950 jetons en entrée, 190 en sortie) ; STT ≈ 0,0002 $ / min ; TTS ≈ 0,0001 $ / réplique.

| Étape | Tours (typique) | Agent / tour | Audio | Coût |
|---|---|---|---|---|
| V1 | 2 | 0,0010 $ | 0,5 min | 0,002 $ |
| V2 (adresse dictée + situations) | 1 STT + 1 | 0,0009 $ | 0,3 min | 0,001 $ |
| V3 | 4 | 0,0012 $ | 1,5 min | 0,005 $ |
| V4b feuille (ou V4 Night ≈ 15 tours) | 6 (15) | 0,0012 $ | 2 (5) min | 0,008 (0,02) $ |
| V5c dictée (12 pièces) | 12 | **0,0018 $** (tableau + 400 jetons de sortie) | 5 min | 0,022 $ |
| V6 | 5 | 0,0011 $ | 2 min | 0,006 $ |
| Confirmations, corrections, reprises (+30 %) | | | | 0,013 $ |
| **Total par dossier** | ≈ 45–60 tours | | ≈ 12 min | **≈ 0,06 – 0,08 $** (TTS ≈ 0,003 $ ; dictée sans voix) |

Repères si l’on montait en gamme (même volume) : Claude Haiku 4.5 (0,0032 $ / tour mesuré) ≈ 0,18 $ ; Claude Sonnet 5.5 (0,0062 $) ≈ 0,35 $ ; STT Voxtral Mini Transcribe (0,003 $ / min, 95 % de champs justes contre 86 % pour Whisper Turbo au banc) : + 0,035 $. À 1 000 dossiers : 60–80 $ avec les défauts actuels.

### 7.2 Latence

Feuille d’étape : ≈ 3–4 s jusqu’aux pastilles (STT 0,8 s + agent 2,5 s), voix ensuite si activée. Dictée : ≈ 3 s par pièce, écoute relancée sans attendre ; réponses locales (oui / non / annule) : < 1 s.

### 7.3 Données personnelles

- Étape `owners` : noms des co-propriétaires envoyés au fournisseur STT et au modèle (Q1) ; **transcript remplacé par `[identité non conservée]`** et valeurs retirées de `extracted` dès le tour traité ; aucune valeur connue envoyée.
- Adresse : STT seulement, transcript non conservé, jamais envoyée au modèle de langage.
- Descriptions et textes libres : motif téléphone / e-mail refusé ; consigne « pas de nom de personne » dans les descriptions.
- Consentement v3 (si Q1 = b) : « Pour les propriétaires, les noms que vous dictez sont transcrits par nos prestataires et ne sont pas conservés dans l’historique. »

### 7.4 Crochet de réévaluation

- Vue `agent_step_stats` (par étape × modèle × semaine) : tours, coût moyen (`cost_usd`), latences, taux de `invalid_output`, rejets par raison, **taux d’annulation** (`undone`), **taux de correction** (`correction: true`), confirmations refusées.
- Règle (consignée dans le plan et le runbook) : dès **200 tours réels par étape**, si annulations > 10 %, corrections > 8 %, valeurs rejetées pour ancre manquante > 15 % ou `invalid_output` > 3 % → relancer le banc sur cette étape et basculer **cette étape seule** par secret (`OPENROUTER_MODEL_AGENT_ROOMS=anthropic/claude-haiku-4.5`, `OPENROUTER_MODEL_STT=mistralai/voxtral-mini-transcribe`), sans republier l’app. Revue au plus tard à la fin de la phase de test.

### 7.5 Banc d’essai étendu

`supabase/bench/utterances.json` : + 40 phrases **enregistrées sur l’iPhone** (bruit de fond, voix différentes) : V3 (8), V4b types EPIC-13 (6), dictée de pièces (14 dont 4 multi-pièces, 3 avec description, 2 dimensions « 4 sur 3 »), corrections (6), confirmations / annulations locales (4), injection et hors sujet (2). Mesures : champs justes, **valeurs fausses enregistrables**, pièces mal désignées, coût, latence ; comparaison Gemini 3.5 Flash-Lite / Haiku 4.5 et Whisper Turbo / Voxtral.

---

## 8. (f) Risques et parades

| Risque | Effet | Parade |
|---|---|---|
| Valeur inventée ou déformée (STT « 18 » pour « 80 », modèle qui complète) | surface ou année fausse au dossier | citation littérale + ancre numérique / lexicale ; pastille visible « Compris » ; « Dicté » sur le champ ; annulation ; confirmation des remplacements forts ; l’expert vérifie avant certification |
| Mauvaise pièce modifiée | une surface écrase la mauvaise ligne | références `R*`, désignation contrôlée, question sur ambiguïté, `create` sur un type existant → confirmation, suppression toujours confirmée, diff `38 → 40 m²` |
| Doublons de pièces (même pièce dictée deux fois) | surface habitable gonflée | règle 3 de §4.3, total courant visible pendant la dictée, récapitulatif oral final |
| Niveau supposé | pièce au mauvais niveau | jamais déduit par l’IA : défaut de l’écran (dernière pièce), affiché, modifiable |
| Description qui « embellit » | texte non dit, promesse au futur acheteur | couverture ≥ 80 % des mots, pas de chiffre nouveau, longueur bornée, éditable ; consigne « factuel, sans adjectif ajouté » |
| Type de bien changé par erreur | étapes masquées | confirmation obligatoire ; réponses masquées mais conservées (EPIC-13 Q9) |
| Données d’identité (V1) chez les prestataires et dans le journal | RGPD | Q1 ; transcript effacé après le tour ; aucune valeur connue envoyée ; consentement v3 ; téléphone et e-mail exclus |
| Adresse envoyée à un modèle de langage | RGPD | dictée simple (STT seul), géocodage, transcript non conservé |
| Injection de consigne dans une description | texte piégé lu par l’expert ou réinjecté au prompt | données balisées et chevrons neutralisés (existant) ; descriptions **non renvoyées** au prompt (seulement nom · niveau · surface) |
| JSON tronqué avec beaucoup de pièces | tour perdu | 12 opérations max, `maxTokens` 2 500, nouvelle tentative (existant), « répétez » |
| Coût en hausse (tours plus longs, dictées) | budget | défauts les moins chers, dictée sans TTS, réponses locales, quotas inchangés, suivi §7.4 |
| Concurrence avec l’écran (saisie pendant un tour) | valeur écrasée | inputs du formulaire désactivés pendant « réflexion » ; application sur l’état courant, annulable |
| Dépendance à EPIC-13 (fichiers communs : `schema.ts`, `handlers.ts`, pages d’étape, profil) | conflits | démarrage après fusion d’EPIC-13 ; tranche V0 de remise à niveau de l’inventaire |
| Maquettes absentes (feuille d’étape, dictée, carte V5, champ description) | allers-retours | composants Night existants (V6) ; demande d’ajout au canevas ; validation sur iPhone |

---

## 9. (g) User stories EPIC-14

Détail et statuts dans [`EPIC-14-voix-etendue.md`](../epics/EPIC-14-voix-etendue.md).

### US-14.1 · Un micro sur chaque étape
*En tant que vendeur, je veux pouvoir répondre à la voix sur n’importe quelle étape, pour éviter de taper.*
- [ ] Le micro apparaît sur V1, V2, V3, V4b, V5c et V6 quand l’étape a des champs dictables pour le type du bien (table §2.8) et que la voix est disponible ; jamais sur V7, ni sur un dossier envoyé.
- [ ] Il ouvre une feuille vocale propre à l’étape, avec une intro qui dit ce qu’on peut dicter.
- [ ] Ce que l’agent retient apparaît en pastilles et dans le formulaire (étiquette « Dicté »), sans être enregistré avant « Continuer ».
- [ ] Le formulaire reste utilisable ; fermer la feuille ne perd rien.

### US-14.2 · Plusieurs réponses en une phrase
*En tant que vendeur, je veux tout dire d’un trait.*
- [ ] « Achetée 320 000 € en 2012, pour une mutation, jamais estimée » remplit les quatre champs de V3.
- [ ] Chaque valeur retenue a une citation littérale et une ancre (nombre ou mot-clé) dans ma phrase ; sinon elle devient une question.
- [ ] Une information d’une autre étape n’est pas écrite ; l’agent dit où elle sera demandée.

### US-14.3 · Dictée de pièces
*En tant que vendeur, je veux décrire mes pièces une par une à voix haute pour remplir le tableau des surfaces.*
- [ ] V5 propose « Dicter mes pièces » ; V5c ouvre la dictée par le micro.
- [ ] « Le séjour fait 38 m² au rez-de-chaussée, parquet chêne, double vitrage » crée la pièce avec ces cinq valeurs ; plusieurs pièces dans une phrase créent plusieurs lignes ; les chambres sont numérotées.
- [ ] Un niveau non dit reprend celui de la pièce précédente (affiché, modifiable), jamais inventé.
- [ ] L’écoute reprend aussitôt après chaque pièce ; la liste des pièces dictées et le total habitable sont visibles.
- [ ] « Terminer » : récapitulatif (« 9 pièces pour 115 m² habitables. Est-ce correct ? »).
- [ ] Les pièces dictées sont enregistrées au « Tout est correct, continuer » avec `source = voice`, et la surface habitable / annexes se recalculent comme à l’écran.

### US-14.4 · Description des pièces
*En tant que vendeur, je veux dicter ce qui caractérise chaque pièce.*
- [ ] Chaque pièce a une description facultative (300 caractères), dictée ou saisie dans la fiche pièce.
- [ ] La description ne contient que ce que j’ai dit (pas de chiffre ni de qualité ajoutés) ; elle apparaît dans le tableau V5c et l’aperçu des données.

### US-14.5 · Corriger et annuler à la voix
*En tant que vendeur, je veux corriger l’agent sans toucher l’écran.*
- [ ] « Non, plutôt 40 m² » remplace la dernière valeur concernée, signalée « corrigé ».
- [ ] « Annule » annule le dernier tour ; chaque pastille a sa croix ; « Annuler » après fermeture annule toute la session.
- [ ] Une valeur dictée qui remplace une valeur existante s’affiche « a → b » ; un écart fort demande confirmation.

### US-14.6 · Confirmer ce qui compte
*En tant que vendeur, je veux que l’agent me demande confirmation avant un changement important.*
- [ ] Changement de type, suppression (pièce, estimation, co-propriétaire), co-propriétaire dicté, confiance moyenne, pièce ambiguë : « Est-ce correct ? » avec Oui / Non touchables ou dits.
- [ ] « Oui », « non », « annule », « terminé » sont reconnus sans attendre l’agent.

### US-14.7 · Propriétaires et adresse à la voix
*En tant que vendeur, je veux dicter qui possède le bien et son adresse, sans exposer mes coordonnées.*
- [ ] V1 : le nombre de propriétaires et les noms des co-propriétaires sont dictables (selon Q1), toujours confirmés ; téléphone et e-mail restent à l’écran.
- [ ] V2 : l’adresse dictée remplit le champ de recherche, je choisis la suggestion ; les parcelles restent sur la carte ; les servitudes sont dictables.
- [ ] Les noms et l’adresse dictés ne sont pas conservés dans l’historique de l’agent ; l’adresse n’est jamais envoyée au modèle de langage.

### US-14.8 · Contexte et technique pour tous les types
*En tant que vendeur d’un garage, d’un terrain ou d’un local, je veux aussi répondre à la voix.*
- [ ] V3 et V4b sont dictables pour les 8 types, avec leurs champs EPIC-13 (précision du type, surface utile, niveau, équipements).
- [ ] L’audit vocal V4 « Night » reste proposé pour maison, appartement et autre.
- [ ] Le serveur refuse une étape non vocale pour le type (parité app / serveur testée).

### US-14.9 · Coût et qualité suivis
*En tant que porteur de projet, je veux maîtriser le coût et la qualité de la voix étendue.*
- [ ] Coût et qualité par étape et par modèle consultables (vue `agent_step_stats`) : tours, coût, rejets, annulations, corrections.
- [ ] Le modèle de l’agent peut être changé pour une seule étape par secret, sans republier l’app.
- [ ] Banc étendu (40 phrases enregistrées) rejoué avant de fixer les défauts ; quotas inchangés sauf décision.

---

## 10. Découpage (tranches de 1 à 2 h, un agent codeur chacune)

Prérequis : **EPIC-13 fusionné dans `main`** puis `main` fusionné dans `feat/epic-14-voix-etendue`.

| # | Tranche | Fichiers possédés (exclusifs) | Dépend de |
|---|---|---|---|
| V0 | **Remise à niveau** : relire le code fusionné d’EPIC-13 (profils, colonnes, bornes réelles de l’écran), corriger l’inventaire §2 et la parité ; journal | `docs/plans/2026-10-02-voix-etendue.md` | EPIC-13 fusionné |
| V1 | **Migration** `voix_etendue` (`rooms.description`, `rooms.source` + `voice`, `agent_sessions.step`, `agent_turns.undone`, vue `agent_step_stats`) ; dry-run, push, sonde RLS | `supabase/migrations/2026…_voix_etendue.sql` | V0 |
| V2 | **Registre d’étapes** (refactor sans changement de comportement : `technical` + `lifestyle` déplacés, champs EPIC-13 de `technical`) ; tests existants verts | `supabase/functions/_shared/agent/schema.ts`, `…/agent/steps/**`, `supabase/functions/tests/agent_schema*` | V0 |
| V3 | **`property_repository`** : `Room.description`, `RoomSource.voice` ; tests 100 % | `packages/property_repository/**` | V0 |
| V4 | **Validation** : types `bool` / `money` / `month` / `text` (couverture), `french_numbers.ts`, ancres, confirmations, corrections, `out_of_step` ; tests | `…/agent/validate.ts`, `…/agent/french_numbers.ts`, `supabase/functions/tests/agent_validate*`, `…/tests/french_numbers*` | V2 |
| V5 | **Étapes `owners`, `location`, `context`** (schémas, consignes, entités co-propriétaire / estimation) ; tests | `…/agent/steps/owners.ts`, `location.ts`, `context.ts`, tests associés | V4 |
| V6 | **Étape `rooms`** (entités, références `R*`, désignation, `copy_from`, dimensions) ; tests | `…/agent/steps/rooms.ts`, `…/agent/rooms.ts`, tests associés | V4 |
| V7 | **Handlers / prompt / config / db** : corps et réponse étendus, refus étape × type (fixture `voice_steps`), effacement `owners`, dictée simple dans `agent-transcribe`, modèle par étape, `undone` ; déploiement des trois fonctions | `…/agent/handlers.ts`, `prompt.ts`, `config.ts`, `db.ts`, `supabase_db.ts`, `supabase/functions/agent-*/**`, `supabase/functions/tests/fixtures/property_type_profiles.json`, `…/tests/agent_handlers*` | V1, V5, V6 |
| V8 | **Banc étendu** (40 phrases enregistrées sur l’iPhone, rapport) | `supabase/bench/**` | V7 |
| V9 | **`agent_repository`** : nouveaux paramètres, `entityOps`, `confirmations`, `outOfStep`, `transcribeOnly` ; tests | `packages/agent_repository/**` | contrats figés en V7 |
| V10 | **Cœur voix app** : `StepVoiceSheet`, `VoiceEdits`, `LocalVoiceCommands`, `DictatedTag`, extension de `VoiceConversationCubit` (brouillon, mode dictée sans voix, écoute enchaînée, confirmations) ; `PropertyTypeProfile.voiceSteps` / `voiceAudit` ; consentement v3 ; l10n `voiceSheet*` | `lib/seller_tunnel/voice/**`, `lib/seller_tunnel/models/property_type_profile.dart` (+ test), `lib/ui/components/voice/**` (si nouveaux widgets) | V9 |
| V11 | **V1 + V2** : `OwnersCubit` / `LocationCubit.voiceTurnApplied`, dictée d’adresse, marqueurs ; l10n `ownersVoice*`, `locationVoice*` | `lib/seller_tunnel/steps/owners/**`, `lib/seller_tunnel/steps/location/**` | V10 |
| V12 | **V3** : `PropertyContextCubit.voiceTurnApplied` (type confirmé, estimations) ; l10n `contextVoice*` | `lib/seller_tunnel/steps/property_context/**` | V10 |
| V13 | **V4b** : feuille vocale (en plus du lien V4 Night pour les logements), champs EPIC-13 ; l10n `technicalVoice*` | `lib/seller_tunnel/steps/technical/**`, `lib/seller_tunnel/steps/voice_audit/**` | V10 |
| V14 | **V5 / V5c dictée** : carte V5, feuille de dictée, `SurfacesCubit.voiceTurnApplied`, description (fiche + tableau) ; l10n `methodVoice*`, `surfacesVoice*`, `surfacesDescription*` | `lib/seller_tunnel/steps/method/**`, `lib/seller_tunnel/steps/surfaces/**` | V3, V10 |
| V15 | **V6** sur la feuille générique + ouverture terrain / local ; aperçu V8 (description des pièces) ; l10n `lifestyleVoice*`, `submitted*` | `lib/seller_tunnel/steps/lifestyle/**`, `lib/seller_tunnel/steps/submitted/widgets/dossier_summary_sheet.dart` | V10 |
| V16 | **Docs & vérification** : epic, plan (journal), `CLAUDE.md` (voix étendue), spec du tunnel (§2 V5c description, V5 carte), runbook « suivi coût voix », politique de confidentialité, test iPhone de bout en bout (latence, coût d’un dossier) | `docs/**`, `CLAUDE.md` | toutes |

Vagues : **0** = V0 · **1** = V1, V2, V3 · **2** = V4 · **3** = V5, V6 · **4** = V7 · **5** = V8, V9 · **6** = V10 · **7** = V11, V12, V13, V14, V15 (dossiers disjoints) · **8** = V16.
ARB : lecture-modification-écriture JSON puis `flutter gen-l10n` immédiatement ; une seule tranche écrit dans `lib/l10n/arb/*` à la fois dans la vague 7 (ordre V11 → V12 → V13 → V14 → V15), préfixes distincts. Chaque tranche est contrôlée par un agent indépendant (tests 100 %, revue, rendu 390×844) avant commit.

---

## 11. Hors périmètre

- Conversation unique qui remplit tout le tunnel d’un trait (Q3, plus tard).
- Interruption de l’agent pendant qu’il parle (barge-in), temps réel / flux.
- Extraction depuis un plan ou une photo (V5 « Importer un plan » reste un dépôt de fichier) ; scan AR V5b.
- Agent « Une question ? » (V8 / V8b), voix sur V7.
- Reconnaissance vocale sur l’appareil.

---

## 12. Questions ouvertes (porteur de projet)

1. **Propriétaires (V1) à la voix** : (a) rien à la voix ; (b) **nombre de propriétaires + noms des co-propriétaires, toujours confirmés, non conservés dans l’historique ; téléphone et e-mail à l’écran** (proposé) ; (c) tout, y compris téléphone et e-mail.
2. **Adresse (V2)** : (a) **dictée simple (transcription seule) dans le champ de recherche, suggestion à toucher** (proposé) ; (b) pas de voix pour l’adresse, seulement les servitudes ; (c) via l’agent (l’adresse part au modèle de langage).
3. **Portée d’une session** : (a) **feuille propre à chaque étape** (proposé : le vendeur voit les champs remplis) ; (b) une conversation globale qui remplit tout le tunnel ; (c) (a) maintenant, (b) plus tard.
4. **V4b** : (a) **le micro ouvre la feuille d’étape, l’audit Night V4 reste accessible par un lien « Conversation guidée »** (proposé) ; (b) le micro ouvre toujours V4 Night (comme aujourd’hui) ; (c) V4 Night supprimé au profit de la feuille.
5. **Voix de l’agent** : (a) **parle dans les feuilles d’étape, se tait pendant la dictée de pièces (texte + vibration), récapitulatif final parlé** (proposé) ; (b) parle toujours ; (c) réglage par l’utilisateur seulement.
6. **Politique de confirmation** : (a) **appliquer tout de suite avec annulation, confirmer seulement les changements risqués (§5.3)** (proposé) ; (b) confirmer chaque tour ; (c) ne jamais confirmer.
7. **Description des pièces** : (a) **texte libre de 300 caractères par pièce** (proposé) ; (b) (a) + liste d’atouts structurés (cheminée, placards, cuisine équipée, balcon, climatisation, vue…) ; (c) pas de description.
8. **Traçabilité « dicté »** : (a) **provenance « Déclaré », `rooms.source = voice`, détail dans le journal** (proposé) ; (b) nouvelle provenance « Dicté » visible par l’expert ; méthode V5 : `manual` (proposé) ou nouvelle valeur `voice` ?
9. **Quotas** : (a) **inchangés (120 tours, 20 min d’audio par jour)** (proposé pour la phase de test) ; (b) 200 tours / 30 min ; (c) plafond par dossier en plus.
10. **Surface par dimensions** (« 4 sur 3 ») : (a) **calculée par le serveur à partir des deux nombres dits, affichée « 4 × 3 m = 12 m² »** (proposé) ; (b) refusée, l’agent demande la surface.
11. **V7 Documents** : (a) **pas de micro** (proposé) ; (b) commandes vocales « scanne ma taxe foncière » qui ouvrent le scanner.
12. **Voix pour les types non logement** (EPIC-13 l’avait réservée à maison / appartement / autre) : (a) **feuilles d’étape pour tous les types, audit Night pour les logements** (proposé) ; (b) garder la restriction d’EPIC-13.
13. **Modèles** : (a) **mêmes défauts les moins chers partout, bascule par étape selon le suivi §7.4** (proposé) ; (b) modèle plus fort pour la dictée de pièces dès le départ (Haiku 4.5 ≈ +0,03 $ par dossier) ; (c) passer le STT à Voxtral Mini Transcribe (+ 0,035 $ par dossier, nettement meilleur sur le vocabulaire du bâtiment).

---

## 13. Remise à niveau V0 (code fusionné d’EPIC-13)

Inventaire §2 relu contre le code fusionné (`PropertyTypeProfile`, écrans, migrations `multi_biens*`) ; corrections :

- **V2** « Autre » (`special_situation_other`) : borne de l’écran **300** caractères (et non 120).
- **V3** : bornes confirmées (`PropertyContextState`) — années ≥ 1900, montants 1 000 € – 100 M€, précision et usage ≤ 100 car., agence ≤ 120, logements 2…500 ; « Construit par vous ? » pour maison, appartement, dépendance, autre (et type non choisi).
- **V4b** : `usable_area_m2` **1…2 000** m² (`TechnicalState.minUsableArea`, `maxArea`) ; année de construction **obligatoire pour l’immeuble** aussi ; les colonnes par type sont exactement celles de `technicalFields` (table §2.4 confirmée) — la parité est maintenant **testée** (fixture `technical`, `parking_features` d’une dépendance = électricité / eau).
- **V6** : l’étape existe pour M, A, T, L, I, Au (pas S ni D) ; bruit et vis-à-vis seulement si `asksNeighbourhood` (pas L).
- **Modèle app** : `PropertyTypeProfile.voice` est devenu **`voiceAudit`** (V4 Night) + **`voiceSteps` / `hasVoice(step)`** (feuilles d’étape) ; `Room.source` était un `MeasurementMethod` → nouvel enum **`RoomSource`** (`scan`, `plan`, `manual`, `voice`) ; un co-propriétaire dicté n’a pas de téléphone : l’état V1 exige désormais que chaque co-propriétaire soit complet (« À compléter : téléphone »).
- **Base** : la migration `agent_conversations` était déjà appliquée → la contrainte `agent_sessions.step` est remplacée dans la **nouvelle** migration `20261002111222_voix_etendue` (avec `rooms.description`, `rooms.source = voice`, `agent_turns.undone`, vue `agent_step_stats`).
- **Routes** : V5c accepte `?dictee=1` (carte V5 « Dicter mes pièces ») ; aucune autre route ajoutée.

## 14. Choix par défaut en attendant le porteur de projet

Les 13 questions du §12 n’étant pas encore tranchées, l’option **recommandée (« proposé »)** de chacune est implémentée. Toutes sont réglables sans refonte : constantes `VOICE_DEFAULTS` (`supabase/functions/_shared/agent/defaults.ts`) côté serveur et `VoiceDefaults` (`lib/seller_tunnel/voice/voice_defaults.dart`) côté app, secrets Supabase pour les modèles et constantes `LIMITS` pour les quotas.

| Q | Choix appliqué | Où le changer |
|---|---|---|
| Q1 Propriétaires | **(b)** type de propriété + prénom / nom des co-propriétaires, toujours confirmés, transcript effacé du journal ; téléphone et e-mail à l’écran. Remarque : l’option listée en premier est (a), mais (b) est l’option recommandée par le plan — (a) se règle par `coOwnerNames = false` (serveur et app) | `VOICE_DEFAULTS.coOwnerNames`, `VoiceDefaults.coOwnerNames` |
| Q2 Adresse | **(a)** dictée simple (`agent-transcribe` `mode=dictation`, jamais envoyée au modèle de langage ni gardée au journal) dans le champ de recherche ; le vendeur choisit la suggestion | `addressDictation` |
| Q3 Portée | **(a)** une feuille par étape | — (structure) |
| Q4 V4b | **(a)** le micro ouvre la feuille d’étape ; l’audit Night V4 reste accessible par le lien « Conversation guidée » (logements) ; la redirection V3 → V4 reste inchangée | `VoiceDefaults.technicalSheet` |
| Q5 Voix de l’agent | **(a)** parle dans les feuilles, se tait pendant la dictée de pièces (texte + vibration), récapitulatif final **parlé** (calculé par le serveur sans modèle) | `VoiceDefaults.silentRoomsDictation` |
| Q6 Confirmation | **(a)** appliqué tout de suite, annulable ; confirmation pour : changement de type, suppressions, co-propriétaire, confiance 0,5–0,7, écart fort (surface ±50 %, année ±20 ans), « aucune » qui efface des situations, pièce existante redictée | `confirmFrom`, `strongChange` |
| Q7 Description | **(a)** texte libre de 300 caractères par pièce | `Room.descriptionMaxLength` + contrainte SQL |
| Q8 Traçabilité | **(a)** provenance « Déclaré », `rooms.source = voice`, détail au journal ; méthode V5 `manual` | `VoiceDefaults.dictationIsManualMethod` |
| Q9 Quotas | **(a)** inchangés : 120 tours et 20 min d’audio par jour | `LIMITS` (`_shared/agent/db.ts`) |
| Q10 « 4 sur 3 » | **(a)** surface calculée (« 4 × 3 m » affiché), les deux nombres doivent être dans la citation | `areaFromDimensions` |
| Q11 V7 | **(a)** pas de micro | — |
| Q12 Types non logement | **(a)** feuilles d’étape pour tous les types, audit Night pour les logements | `VOICE_DEFAULTS.allTypes`, `VoiceDefaults.allTypes` |
| Q13 Modèles | **(a)** mêmes défauts partout ; bascule **par étape** par secret `OPENROUTER_MODEL_AGENT_<ÉTAPE>` selon la vue `agent_step_stats` | secrets Supabase |

Écarts assumés (à valider) :
- **Suppression d’un co-propriétaire à la voix : non prise en charge** (les noms ne sont jamais envoyés au modèle, il ne peut donc pas les désigner) ; elle reste à l’écran.
- Les réponses « oui / non / annule / terminé » reconnues localement ne coûtent **pas d’appel au modèle**, mais leur transcription compte comme un tour dans le quota (la fonction de réservation compte toutes les lignes du journal).
- Si la feuille V1 est fermée entre la transcription et la réponse de l’agent, ce transcript (noms) reste au journal ; tous les autres chemins (réponse, échec, JSON illisible) l’effacent.
- L’étiquette « Dicté » est posée sur les questions à valeur unique (et pièces, co-propriétaires, situations) ; les listes de V4b (chauffage, extérieurs) n’en portent pas — les pastilles de la feuille et l’instantané « Annuler » couvrent le cas.

---

## Journal d’exécution

- 2026-10-02 : plan rédigé (aucun code), EPIC-14 créé ; en attente des arbitrages et de la fusion d’EPIC-13.
- 2026-10-02 (V0) : inventaire relu contre le code fusionné d’EPIC-13 (§13) ; choix par défaut appliqués en attendant le porteur de projet (§14).
- 2026-10-02 (V1) : migration `20261002111222_voix_etendue` (sonde dans une transaction annulée — vue lisible par `service_role` seulement, écritures du journal toujours interdites aux clients, `rooms.description` insérable — puis dry-run et push).
- 2026-10-02 (V2–V7) : registre d’étapes `_shared/agent/steps/` (owners, location, context, technical, rooms, lifestyle) ; `french_numbers.ts` (nombres dits), `anchors.ts` (ancres numériques / lexicales, couverture du texte libre), `rooms.ts` (références R*, désignation, ambiguïtés, doublons) ; `validate.ts` (entités, confirmations, corrections, hors étape, typographie) ; prompt par étape ; handlers (contexte de l’app, refus étape × type, effacement V1, dictée d’adresse, récapitulatif de pièces sans modèle, tours annulés) ; modèle par étape. 144 tests Deno ; fonctions `agent-transcribe`, `agent-turn`, `agent-speech` redéployées.
- 2026-10-02 (V9–V15) : `agent_repository` (étapes, contexte, entités, confirmations, dictée, récapitulatif, `markUndone`) ; cœur voix app (`VoiceForm` / `VoiceFormMixin` avec annulation par rejeu, `StepVoiceSheet`, `LocalVoiceCommands`, `VoiceDictationCubit`, « Dicté », consentement v3) ; V1, V2, V3, V4b, V5 / V5c (dictée, description), V6 migré sur la feuille générique, description des pièces dans l’aperçu V8.
- 2026-10-02 (V8) : **non fait** — le banc étendu demande 40 phrases enregistrées sur l’iPhone.

