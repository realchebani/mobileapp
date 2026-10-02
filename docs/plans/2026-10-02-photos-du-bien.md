# Photos du bien (v1 de la capture visuelle) — plan d’implémentation

> EPIC-15. Date : 2026-10-02. Étude préalable : [`2026-10-02-capture-visuelle-etude.md`](2026-10-02-capture-visuelle-etude.md) (options 6, 6 bis et 7).
> Statut : livré, à valider sur l’iPhone (voir le journal d’exécution en fin de document).

## 1. Contexte et arbitrages

Le porteur de projet a retenu (2026-10-02, section « Arbitrages » de l’étude et brief EPIC-15) :

| # | Arbitrage | Conséquence dans ce plan |
|---|---|---|
| Q1 | Photos pour **l’expert et l’annonce** (une seule capture, assez documentée pour l’analyse de l’expert, défauts compris) ; l’outil devra aussi être proposé **à la mise en vente** (V11a, EPIC-08 non construit) | Composant `RoomPhotosPage` + `RoomPhotosCubit` indépendant du tunnel (§4.6, point d’accroche V11a). Conseils de prise de vue orientés « constat » (montrer aussi les défauts). |
| Q2 | Capture **depuis chaque pièce dans V5c** | Action « Photos » sur chaque ligne du tableau et dans la fiche pièce ; écran « Photos de la pièce ». |
| Q3 | **Au moins une photo par pièce principale** pour envoyer le dossier | Règle bloquante en V7 (pièces `is_main`, seulement pour les types qui ont des pièces) + indicateurs en V5c. |
| Q4 | **Pas de floutage automatique en v1** (backlog après tests) | Consigne à l’écran « Personne dans le champ » ; l’IA signale les personnes visibles ; la photo est marquée « à reprendre ou supprimer ». |
| Q5 | **IA de vision via OpenRouter avec consentement** au premier usage | Écran de consentement « Analyse des photos » (v1), modèle par secret, le moins cher par défaut, `data_collection: deny`. Suggestions = propositions acceptées par le vendeur. Jamais de surface ni de mesure. |
| Q6 | **Lecture d’un plan en v1** | V5 « Lire un plan » : scanner VisionKit (déjà intégré) ou photothèque ; l’IA extrait uniquement les pièces et surfaces imprimées ; validation ligne par ligne ; pièces `source = plan`, provenance « Extrait d’un document ». |
| Q7 | **Retirer la carte V5 « Scanner avec la caméra »** | Carte supprimée. |
| — | Contrôles qualité **sur l’appareil** avant envoi (netteté, lumière, inclinaison) avec des plugins MIT/BSD/Apache | `camera` (BSD-3) + `sensors_plus` (BSD-3) pour l’écran de prise de vue et le niveau ; `image` (MIT, déjà présent) en isolat pour la luminosité et la netteté. |

Questions 8 à 10 de l’étude (visite virtuelle dans l’offre, pilote 3D, Supabase Pro) : hors périmètre v1.

## 2. Modèle de données

Migration `*_room_photos.sql` (additive uniquement).

### 2.1 Table `room_photos`

| Colonne | Type | Règle |
|---|---|---|
| `id` | uuid PK | choisi par l’app (`generateUuidV4`) : insertion rejouable sans doublon |
| `property_id` | uuid | FK `properties` (cascade) |
| `room_id` | uuid | FK composite `(room_id, property_id)` → `rooms (id, property_id)` (cascade) : la pièce appartient au même bien |
| `storage_path` | text unique | `<uid>/<property>/photos/<room>/<id>.jpg` (politique restrictive : dossier de l’utilisateur et du bien) |
| `width`, `height` | smallint | > 0 |
| `size_bytes` | integer | 1 octet à 20 Mo |
| `sort_order` | smallint | ≥ 0 (ordre dans la pièce, la première = photo principale) |
| `source` | text | `camera` / `library` |
| `quality` | jsonb | contrôles sur l’appareil : `{brightness, sharpness, tilt_deg, issues[]}` |
| `analysis` | jsonb | résultat de l’IA (**écrit par l’Edge Function uniquement**) |
| `taken_at` | timestamptz | |
| `created_at`, `updated_at` | timestamptz | trigger `seller_tunnel_set_updated_at` |

- **Limites** (trigger `room_photos_check_limits`, erreur `room_photo_limit_reached`) : **12 photos par pièce**, **150 par bien**.
- **`rooms.photos_count`** tenu par la base : trigger après insertion / suppression sur `room_photos` + trigger avant écriture sur `rooms` qui recalcule le nombre (la valeur envoyée par l’app est ignorée : un upsert de V5c ne peut pas l’écraser).
- **RLS** : lecture par le propriétaire du bien ; insertion / mise à jour / suppression seulement si le bien est `draft` ou `submitted` (même verrou que les autres tables enfants). Droits : `select, delete` ; `insert` colonne par colonne (sans `analysis`) ; `update (sort_order)`.
- **Storage** : même bucket privé `property-documents` (20 Mo, JPEG accepté) ; ses politiques existantes (`lock_document_files`) vérifient déjà le dossier `<uid>` et le bien ouvert (2ᵉ segment) : aucune politique Storage nouvelle. `PropertyRepository.deleteProperty` supprime aussi les photos (sous-dossiers non listés par Storage).
- `property_documents` : le plan lu en V5 est un document `kind = plan` (image JPEG/PNG) ; l’Edge Function écrit son résultat dans `extracted.plan_reading` (colonne réservée au backend) ; `status` reste `received` (« Analysé » est réservé à l’expert). Il apparaît donc aussi en V7.

### 2.2 Journal et quotas IA : `vision_requests`

Lecture seule pour le propriétaire ; écrit par les Edge Functions (service role), comme `agent_turns`.

| Colonne | Contenu |
|---|---|
| `owner_id`, `property_id` | appelant vérifié, bien |
| `kind` | `room_photo` / `plan` |
| `target_id` | photo ou document |
| `model`, `tokens_in`, `tokens_out`, `cost_usd`, `ms` | coût et latence (usage OpenRouter) |
| `error` | `in_progress`, `invalid_output`, `upstream`… |

Fonction `vision_reserve_request` (service role seulement) : vérifie le quota du jour et insère la ligne dans la même transaction (verrou consultatif par utilisateur). **Quotas** : 200 analyses de photos et 10 lectures de plan par utilisateur et par jour (constantes `_shared/vision/db.ts`). Une photo ou un plan déjà analysé n’est jamais renvoyé au modèle (réponse en cache).

## 3. Fonctions IA (Edge Functions)

Code commun `supabase/functions/_shared/vision/` (config, client base de données appelant + service role, prompts, schémas JSON stricts, validation) ; tests Deno dans `supabase/functions/tests/vision_*_test.ts`.

| Fonction | Entrée | Sortie | Règles |
|---|---|---|---|
| `vision-room` | `{photo_id}` | `{analysis}` | Photo du bien **brouillon** de l’appelant (RLS) ; image téléchargée avec le JWT de l’appelant (≤ 8 Mo) ; sortie validée par liste blanche : `room_kind` (puces de V5c), `floor_covering` (liste V5c), `glazing`, `condition_notes` (≤ 4 × 120 caractères, **aucun chiffre** : une note avec un nombre est rejetée), `personal_items` (≤ 6), `people_visible`, `quality_issues` (`dark`, `blurry`, `tilted`, `cluttered`, `overexposed`). Aucune surface, aucune dimension. |
| `plan-reader` | `{document_id}` | `{reading}` | Document `plan` image du bien brouillon ; l’IA ne renvoie **que** ce qui est imprimé : pièces (`name`, `area_m2` ou `null`, `level` si indiqué, `kind`), `printed_total_m2` ; contrôles : 40 pièces max, surfaces entre 0,5 et 1 000 m², somme comparée au total imprimé (écart > 5 % ⇒ avertissement). PDF : non lu en v1 (415, le vendeur photographie le plan). |

- Modèle : secret `OPENROUTER_MODEL_VISION` (défaut `google/gemini-3.5-flash-lite`, le moins cher du banc vocal, multimodal), optionnellement `OPENROUTER_MODEL_PLAN` ; fournisseur `data_collection: deny`. Clé `OPENROUTER_API_KEY` (jamais dans l’app).
- **Consentement exigé côté serveur** : l’app envoie `consent: "photo_analysis_v1"` (version de l’écran accepté) ; sans lui, 403 `consent_required`. Le texte visible dans l’image est une donnée, jamais une instruction (consigne des prompts). Constats et objets : tout texte contenant un chiffre, un nombre écrit en lettres ou un mot de mesure (m², mètre, surface, hauteur…) est écarté. Noms de pièces d’un plan : lettres, chiffres, espaces, apostrophes et traits d’union, 40 caractères au plus.
- Les fonctions **n’écrivent jamais le dossier** (pièces, propriété) : seulement `room_photos.analysis`, `property_documents.extracted/status` et le journal. Le vendeur accepte chaque suggestion dans l’app.
- Codes d’erreur : `unauthorized` 401, `not_found` 404, `locked` 409, `quota` 429, `unsupported` 415, `upstream` 502.
- Coût estimé : ≈ 1 500 jetons par photo (image 2 048 px) ⇒ < 0,001 $ par photo, < 0,05 $ par bien ; plan ≈ 0,001 $.

## 4. Écrans et parcours

### 4.1 V5 · Méthode de relevé
- Carte « Scanner avec la caméra » **supprimée**.
- Carte « Lire un plan » (ex-« Importer ou photographier un plan ») active : feuille « Scanner le plan » (VisionKit, 1 page) / « Choisir une photo » ; la note sous les cartes parle désormais des pièces lues sur un plan (plus de mesure au téléphone) ; consentement IA s’il n’a pas été donné (refus ⇒ le plan est seulement déposé pour l’expert, saisie manuelle) ; envoi comme document `plan`, lecture, puis **écran de vérification du plan** (V5-plan) : une ligne par pièce lue (nom, niveau, surface éditable ; case « Garder »), avertissement si la somme ne correspond pas au total imprimé, « Ajouter N pièces » ⇒ pièces écrites (UUID choisis par l’app ; `source = plan` et « Extrait d’un document » seulement pour une ligne gardée telle qu’imprimée, `source = manual` / « Déclaré » dès que le vendeur corrige ou complète la ligne), `measurement_method = plan`, ouverture de V5c. Si le bien a déjà des pièces : « Ajouter à mes pièces » ou « Remplacer mes pièces » (les pièces existantes et leurs photos sont supprimées, avec avertissement). Une lecture ratée se relance par « Relire le dernier plan » sans nouvel envoi (le serveur ne relit pas un plan déjà lu).

### 4.2 V5c · Récapitulatif des surfaces (+ photos)
- Chaque ligne : bouton photo avec le nombre de photos ; pièce principale sans photo signalée (« Photo requise ») ; étiquette « Plan » (couleurs de la provenance « Extrait d’un document », rappelée en tête du tableau) pour une pièce lue sur le plan ; une pièce du plan dont le nom ou la surface est corrigé devient saisie (`source = manual`). La surface habitable (ou des annexes) a la provenance `document` quand toutes ses pièces viennent du plan, `declared` sinon.
- Pastilles d’en-tête : « 12 photos » et « Photos requises : 3/4 » (pièces principales photographiées) ; rappel sous le tableau tant qu’il en manque.
- Fiche pièce (édition) : bouton « Photos de la pièce (N) » ; suppression d’une pièce avec photos : avertissement, photos supprimées avec la pièce à l’enregistrement.
- Ouvrir les photos d’une pièce non encore enregistrée l’enregistre d’abord (upsert par id, enregistré aussitôt dans le tunnel).

### 4.2 bis Vie privée
- Les métadonnées EXIF (position GPS, appareil, date) sont retirées sur le téléphone avant l’envoi : photos de l’appareil et de la photothèque, plans et pages scannées (`processPhoto`, `compressPage`).
- Le consentement à l’IA se retire à tout moment : « Désactiver les suggestions de l’IA » (écran des photos) et Compte › « Suggestions de l’IA sur les photos ».

### 4.3 Photos de la pièce (nouvel écran, réutilisable)
- En-tête « Photos · Séjour », rappel « Pièce principale : au moins une photo ».
- Conseils : angle de la pièce, téléphone droit à hauteur de poitrine, lumière, **personne dans le champ**, montrer aussi les défauts (fissures, humidité) pour l’expert.
- Grille des photos (miniatures par URL signée), état d’envoi / d’analyse, badges « Personne visible », « Floue », « Sombre », « Penchée » ; détail d’une photo (feuille) : grande image, contrôles, notes de l’IA, « Mettre en premier », « Supprimer ».
- « Photographier » (écran caméra) et « Photothèque » (sélection multiple). Le consentement à l’IA est demandé à la première photo (une seule fois ; refus mémorisé).
- Carte **Suggestions de l’IA** (si consentement) : type de pièce, revêtement, vitrage (« Appliquer »), constats (« Ajouter à la description »), objets personnels à ranger avant l’annonce. Les valeurs appliquées reviennent dans le formulaire de la pièce de V5c (enregistrées avec « Continuer ») : ce sont des réponses du vendeur (« Déclaré ») ; la proposition de l’IA reste dans `room_photos.analysis` pour l’expert.
- Lien « Activer les suggestions de l’IA » quand le consentement a été refusé, « Désactiver les suggestions de l’IA » quand il est donné.
- Envoi : un échec dont la réponse a pu se perdre (délai dépassé) est vérifié en relisant les photos de la pièce ; le fichier n’est supprimé côté serveur que si la base a refusé la ligne ; « Retirer » une photo non envoyée supprime sa ligne (par id) et son fichier au cas où. Retour système Android : comme le bouton retour, une fois les envois terminés.

### 4.4 Prise de vue (nouvel écran)
- Aperçu `camera` plein écran, grille des tiers, **niveau** (accéléromètre, `sensors_plus`), bandeau « Personne dans le champ · Allumez et ouvrez les rideaux », déclencheur, compteur, « Terminé ».
- Après chaque photo : traitement en isolat (orientation, réduction à 2 048 px, JPEG 85, luminosité, netteté par variance du laplacien, inclinaison au déclenchement) ; si un défaut est détecté, revue « Photo un peu sombre — Reprendre / Garder ». Les photos gardées partent en arrière-plan.
- Seuils v1 (à calibrer sur de vraies photos) : luminosité moyenne < 60 ou > 225 / 255, variance du laplacien < 40, inclinaison > 6°.

### 4.5 Consentement « Analyse des photos » (nouvel écran)
- Même gabarit que le consentement micro : qui traite les images (OpenRouter + fournisseur du modèle, sans conservation ni entraînement), ce qui est proposé (jamais de mesure), ce qui reste (les photos dans le dossier, l’analyse pour l’expert), conseil « personne dans le champ ». Choix mémorisé sur l’appareil (`photo_analysis_consent_v1`, refus mémorisé aussi).

### 4.6 Point d’accroche V11a (mise en vente, EPIC-08)
`RoomPhotosPage` reçoit le bien (id, propriétaire), la pièce et un mode lecture seule ; il ne dépend pas de `SellerTunnelCubit`. V11a pourra l’ouvrir pièce par pièce pour les vendeurs qui n’ont pas pris de photos dans le tunnel, puis sélectionner les photos d’annonce (table / bucket d’annonce à décider avec EPIC-08 ; les lignes `room_photos` d’un dossier verrouillé ne sont plus modifiables).

### 4.7 V7 · Documents et V8 · Aperçu
- V7 : envoi bloqué tant qu’une pièce principale n’a pas de photo (types avec pièces seulement) : message « Ajoutez au moins une photo de : Séjour, Chambre 1 » et bouton « Ajouter les photos » (retour V5c). Le score de transparence compte les photos (poids 15 dans la part documents, proportionnel aux pièces principales photographiées ; conseil « Ajoutez les photos de vos pièces »).
- V8 « Aperçu de mes données » : ligne « Photos » (total et détail par pièce).
- Expert / équipe : runbook `certifier-un-dossier.md` (requête SQL des photos par pièce, lecture dans le bucket, analyse IA à vérifier).

## 5. Tranches

| # | Tranche | Statut |
|---|---|---|
| 1 | Plan, epic, README | ✅ |
| 2 | Migration `room_photos` + `vision_requests` (+ sonde RLS annulée, dry-run, push) | ✅ |
| 3 | `_shared/vision`, `vision-room`, `plan-reader` + tests Deno, déploiement | ✅ |
| 4 | `PropertyRepository` : photos (liste, envoi, suppression, ordre, URLs signées), analyses, lecture de plan, suppression du bien | ✅ |
| 5 | Traitement sur l’appareil + écran caméra + consentement | ✅ |
| 6 | Écran « Photos de la pièce » + suggestions | ✅ |
| 7 | V5c (indicateurs, actions, enregistrement à la demande), V5 (plan, carte retirée) | ✅ |
| 8 | V7 (règle + score), V8 (aperçu), runbook | ✅ |
| 9 | Tests 100 %, analyse, licences, build iOS, rendus | ✅ |

## 6. Hors périmètre / backlog
- ~~Changer l’ordre des photos en une seule requête (RPC)~~ : fait (durcissement, §7).
- ~~Empêcher côté serveur la suppression de la dernière photo d’une pièce principale d’un dossier envoyé~~ : fait (§7).
- ~~Retirer aussi l’EXIF des documents importés tels quels en V7~~ : fait (§7).
- Floutage automatique des visages (Apple Vision ou ML Kit) — après les tests.
- Lecture des plans PDF ; plans sur plusieurs pages en une fois.
- Banc d’essai du modèle de vision sur 30 photos réelles (comme pour la voix), boîtes englobantes des objets personnels.
- Vidéo par pièce, relevé AR, visite 3D (étude, v2/v3).

## 7. Durcissement (2026-10-02, branche `chore/durcissement`)

Corrections techniques, sans changement de comportement à arbitrer (migration `20261002202107_photos_hardening.sql`, additive) :

| Sujet | Avant | Après |
|---|---|---|
| Ordre des photos | une requête par photo déplacée : un échec au milieu laissait un ordre partiel | RPC `reorder_room_photos(room, ids[])` (droits de l’appelant, RLS) : tout ou rien ; id inconnu, en double ou d’un dossier verrouillé ⇒ `room_photos_order_invalid`, rien n’est changé |
| Dernière photo d’une pièce principale | seule l’app (dossier verrouillé à l’envoi) l’empêchait | déclencheur `room_photos_keep_main_photo` : dossier `submitted`, pièce principale, type avec pièces (non choisi, maison, appartement, autre) ⇒ `room_photo_required` ; pas pour l’équipe (sans JWT) ni pour une photo supprimée avec sa pièce ou son bien ; l’app affiche « Cette pièce principale doit garder au moins une photo… » (`RoomPhotoRequiredFailure`) |
| EXIF des documents importés en V7 | fichiers « Fichiers » / « Photothèque » envoyés tels quels | `PhotoProcessor.stripMetadata` (isolat, `image_metadata.dart`) **sans réencodage** : JPEG (APP1 EXIF/XMP, APP13 IPTC, commentaires, données après l’image retirés ; profil ICC, JFIF, Adobe gardés ; orientation conservée dans un EXIF minimal), PNG (`eXIf`, `tEXt`, `zTXt`, `iTXt`, `tIME`), HEIC/HEIF (élément EXIF remplacé par un EXIF vide, XMP par des espaces, taille inchangée) ; **un PDF n’est jamais modifié** ; une image impossible à analyser est envoyée telle quelle (erreur remontée). Vérifié sur une vraie photo d’iPhone géolocalisée en JPEG, HEIC et PNG (plus de GPS ni d’appareil, image toujours lisible) |
| Statut relu à l’écriture (vision) | statut « brouillon » vérifié à la lecture, analyse écrite ensuite par le service role | `vision_save_photo_analysis` / `vision_save_plan_reading` : écriture seulement si le bien est encore brouillon (verrou partagé sur la ligne du bien), sinon 409 `locked` et journal `locked` ; lecture de plan fusionnée dans `extracted` en base (plus d’écrasement d’autres clés) |
| Deux analyses simultanées de la même photo | deux appels au modèle | `vision_reserve_target` : une réservation `in_progress` de moins de 2 min pour la même cible ⇒ `busy` ; la fonction attend alors le résultat (20 s au plus, sinon 409 `busy`) et le renvoie `cached: true` |
| Fichiers orphelins | aucun moyen de les voir | `staff_orphan_files(p_min_age)` (service role) : fichiers du bucket sans ligne `property_documents` (plans compris) ni `room_photos` ; ménage manuel par l’API Storage (runbook `certifier-un-dossier.md` §5), jamais automatique |

Non traité (à arbitrer ou hors technique) : supprimer en base l’ancienne fonction `vision_reserve_request` (inutilisée, gardée : migrations additives) ; empêcher la suppression d’une **pièce** principale d’un dossier envoyé (même logique, mais touche à la règle produit des pièces) ; refuser à l’import une image impossible à nettoyer (aujourd’hui envoyée telle quelle).

## Journal d’exécution
- 2026-10-02 — Plan rédigé ; dépendances `camera` et `sensors_plus` (BSD-3) ajoutées, contrôle des licences OK.
- 2026-10-02 — Migration `20261002162210_room_photos` : sonde RLS dans une transaction annulée (21 contrôles : dossier de l’utilisateur et du bien, pièce du même bien, `analysis` non modifiable par l’app, 12 photos max, compteur `photos_count` tenu même après un upsert de V5c, verrou `in_review`, cascade à la suppression d’une pièce, journal et quota réservés au service role), dry-run puis push.
- 2026-10-02 — `_shared/vision`, `vision-room`, `plan-reader` : 25 tests Deno (validation, handlers avec base et OpenRouter factices) ; déployées. Essai de bout en bout avec un utilisateur jetable (`epic15-e2e@realesty.fr`) : photo analysée en ≈ 3,5 s pour 0,00073 $ (réponse en cache au 2ᵉ appel) ; plan de test lu en ≈ 4,5 s pour 0,0013 $ (6 pièces, WC sans surface laissé vide, total 64 m² retrouvé).
- 2026-10-02 — Dépôt (`PropertyRepository` : photos, URLs signées, analyses, lecture de plan, suppression des photos avec le bien), écrans (Photos de la pièce, Prise de vue, Consentement, Pièces lues sur le plan), V5 / V5c / V7 / V8, runbook ; tests à 100 % (app et paquet), analyse, bloc lint, format, licences OK ; rendus dans `scratchpad/epic15/shots/`.
- 2026-10-02 — Corrections après vérification : EXIF retiré avant l’envoi (photos, plans, pages scannées ; test sans GPS ni appareil), consentement exigé par les fonctions (403 sans lui) et retirable (écran des photos, Compte), prompts et filtres durcis (texte de l’image = donnée, nombres en lettres et mots de mesure, noms de pièces nettoyés), provenance ligne par ligne du plan, « Remplacer mes pièces », « Relire le dernier plan », envoi perdu vérifié / fichier conservé / « Retirer » par id, retour Android, mise en page en grand texte. Fonctions redéployées ; essai de bout en bout refait (403 sans consentement).
- 2026-10-02 — Durcissement (§7) : migration `20261002202107_photos_hardening` (sonde annulée : 32 contrôles — ordre tout ou rien, id étranger / en double / dossier verrouillé refusés, dernière photo d’une pièce principale envoyée refusée mais permise pour l’équipe, une pièce non principale, un terrain, un brouillon ou par cascade ; réservation `busy` / `quota` / périmée ; écriture des analyses refusée hors brouillon et pour un autre propriétaire ; plan fusionné ; orphelins listés, fonctions fermées aux clients — puis dry-run et push) ; `vision-room` et `plan-reader` redéployées après 191 tests Deno ; essai de bout en bout avec un utilisateur jetable supprimé ensuite (réordre, refus d’un id inconnu sans effet, deux analyses simultanées ⇒ une seule ligne au journal, plan fusionné, 3ᵉ suppression refusée `room_photo_required`, orphelins listés, 42501 pour un client) ; app : `reorderRoomPhotos` par RPC, `RoomPhotoRequiredFailure` + message, EXIF retiré des imports V7.
