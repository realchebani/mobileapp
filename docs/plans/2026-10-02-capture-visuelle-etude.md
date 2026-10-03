# Capture visuelle du bien dans le tunnel vendeur : étude de faisabilité

> Document de décision (étude, aucun code). Date : 2026-10-02.
> Question du porteur de projet : « réfléchis à quelle serait la meilleure solution dans le tunnel vendeur pour la capture visuelle du bien. Nous avions pensé à la création d’une visite virtuelle en filmant le bien depuis le téléphone du vendeur ; analyse ce qui est réalisable ou non en partant du plus complexe au plus simple. »
> Sources internes : `CLAUDE.md`, `docs/decisions.md`, `docs/plans/2026-09-30-tunnel-vendeur-spec.md` (V5, V5b, V5c, V7), `docs/plans/2026-10-01-parcours-vendeur-v8b-v19.md` (V11a, V11a-2, V11a-3, §5.5), maquettes `ScanPiece`, `CaptationVisite`, `VisiteVirtuelle`, `GestionEssentiel`.
> Sources externes : liste en fin de document. Les points non vérifiés sont marqués **(à vérifier)**.

---

## 0. En bref

- **Transformer une vidéo amateur en visite virtuelle 3D navigable est techniquement possible en 2026** (Gaussian splatting), mais c’est un produit à part entière : traitement GPU hors Supabase, vidéos de plusieurs centaines de Mo, rendu inégal selon la façon de filmer, et **des surfaces non fiables sans LiDAR**. Ce n’est pas une option v1.
- La maquette V11a-3 promet trois choses de difficulté très différente : une visite 360° (difficile), un **floutage automatique** (faisable), des **surfaces mesurées** à partir de la vidéo (**non fiable sur un iPhone 14 Plus** ; contraire à la règle « l’IA ne produit aucun chiffre » si on les présente comme mesurées).
- **Apple RoomPlan est exclu** sur l’iPhone 14 Plus (pas de LiDAR). ARKit sans LiDAR permet un relevé « coins au sol » de qualité moyenne, comme l’app Mesures d’Apple.
- **Recommandation** : v1 = **photos guidées pièce par pièce dans V5c** (2 à 6 photos par pièce, contrôle qualité sur l’appareil, analyse par un modèle de vision via OpenRouter qui *propose* le type de pièce, le revêtement et le vitrage, floutage des visages sur l’appareil) + **lecture d’un plan photographié** (V5 « Importer ou photographier un plan »). v2 = **vidéo courte par pièce** (sans 3D) et relevé AR facultatif. v3 = **pilote 3D via un service tiers** sur quelques biens avant toute décision de construire.

---

## 1. Contexte et contraintes

| Contrainte | Conséquence pour la capture visuelle |
|---|---|
| iPhone 14 Plus du porteur de projet : puce A15, appareil grand-angle 12 Mpx + ultra grand-angle 0,5×, **pas de LiDAR** | Pas de RoomPlan, pas de `sceneDepth` ARKit, pas de capture d’objet Apple sur iOS. ARKit « world tracking » et détection de plans fonctionnent, moins bien sur les murs unis. |
| Android plus tard (backlog) | Préférer les briques multiplateformes (`camera`, `image_picker`) ; tout ce qui est natif iOS (ARKit, Vision) devra être refait avec ARCore / ML Kit. |
| Dépendances Dart : MIT, BSD-2/3, Apache-2.0 uniquement (contrôle de licences CI) | Exclut `ffmpeg_kit_flutter(_new)` (LGPL-3.0). Les SDK natifs propriétaires (Google ML Kit, Matterport) passent par un plugin MIT mais restent soumis à leurs conditions d’utilisation : à valider explicitement, comme pour Mapbox. |
| Backend Supabase (EU, eu-west-1) ; Edge Functions limitées à **256 Mo de mémoire, 2 s de CPU par requête, 150 s (gratuit) / 400 s (payant) de durée** | Aucun traitement vidéo, assemblage panoramique ou reconstruction 3D ne peut tourner dans une Edge Function. Il faut un service tiers ou un worker GPU (Modal, RunPod…) déclenché par une Edge Function. |
| Supabase Storage : **50 Mo max par fichier en offre gratuite**, 500 Go en Pro ; Pro : 100 Go inclus puis 0,021 $/Go/mois, 250 Go de sortie inclus puis 0,09 $/Go | Photos : sans problème. Vidéo d’une maison (400 Mo à 1,2 Go) : impossible en offre gratuite, et upload reprenable (TUS) nécessaire. |
| IA uniquement via OpenRouter, depuis une Edge Function ; **l’IA reformule ou extrait, elle n’invente aucun chiffre** | Un modèle de vision peut reconnaître une pièce, un revêtement, un défaut de prise de vue ; il ne doit **pas** estimer une surface à partir d’une photo. Une surface issue d’un modèle 3D sans échelle métrique serait un chiffre inventé. |
| Compte Apple gratuit (pas de TestFlight, builds de 7 jours) | Sans effet sur la caméra ; une app tierce (Matterport, Polycam) installée par le vendeur reste possible. |
| Tunnel V1–V7 verrouillé après l’envoi (RLS) | Les médias du tunnel suivent le même verrou ; l’ajout de photos après envoi se fait dans V11a (annonce), avec ses propres règles. |

Ce qui existe déjà et servira : `rooms.photos_count` et `rooms.scan_data jsonb` (prévus pour V5b), `rooms.source` (`scan` / `plan` / `manual`), `properties.measurement_method`, le scanner de documents VisionKit de V7 (`cunning_document_scanner`), `image_picker`, `image` + `pdf` en isolat, le client OpenRouter des Edge Functions (EPIC-06) et, côté EPIC-08 prévu, `listing_photos` + bucket `listing-media` pour V11a.

---

## 2. Les options, de la plus complexe à la plus simple

Échelle d’effort : une *tranche* = 1 à 2 h d’un agent développeur, tests à 100 % compris (convention du projet).

### Option 1 — Vidéo libre → visite virtuelle 3D navigable, pipeline maison (maquettes V11a-2 / V11a-3)

**Ce que fait le vendeur.** Il lance « Visite virtuelle », filme toute la maison en marchant (5 à 10 min), guidé par l’agent (« Tournez lentement vers la droite », indicateurs Luminosité / Stabilité / « Un peu rapide »), pièce par pièce (« Pièce suivante »). Il reçoit la visite 15 à 60 min plus tard, la relit, refilme une pièce ratée, publie.

**Ce que voient les acquéreurs / l’expert.** Une scène 3D photoréaliste dans laquelle on se déplace librement (pas seulement des points de vue fixes), une liste des pièces, éventuellement un plan schématique et une vue « maison de poupée ». Rendu typique du Gaussian splatting : très réaliste là où la caméra est passée, flou ou « nuages » (*floaters*) ailleurs (plafonds, coins, derrière les meubles).

**Approche technique.**
1. Capture : idéalement **dans une session ARKit** (pas une simple vidéo) pour enregistrer images + poses de caméra métriques (l’odométrie visuelle-inertielle d’ARKit fonctionne sans LiDAR). Cela fournit l’échelle réelle et évite l’étape de calcul de poses la plus fragile. Code Swift natif + canal de plateforme (aucun plugin Flutter ne fait l’enregistrement de frames + poses). Sinon, vidéo simple via `camera` (BSD-3).
2. Upload reprenable (TUS) vers Storage (plusieurs centaines de Mo ; offre Pro obligatoire). `tus_client_dart` est MIT mais non maintenu depuis 2023 **(à vérifier)** ; sinon client TUS maison.
3. Worker GPU (ex. Modal : L40S ≈ 1,95 $/h, A100-80 ≈ 2,50 $/h, facturé à la seconde) : extraction d’images nettes, poses (si absentes) avec **COLMAP / GLOMAP (BSD-3)**, entraînement **gsplat / nerfstudio Splatfacto (Apache-2.0)**, compression (**SPZ de Niantic, MIT**, ou SOG de PlayCanvas), floutage des visages sur les images d’entrée avant entraînement.
   - Attention aux licences : l’implémentation d’origine de l’Inria (3DGS) est **non commerciale** ; MASt3R/DUSt3R (Naver) sont **non commerciales** (CC BY-NC-SA) ; VGGT (Meta, reconstruction « feed-forward » très rapide) a une licence propre, une variante commerciale existerait **(à vérifier)**.
4. Visionneuse : page web dans `webview_flutter` (BSD-3) avec **Spark (MIT)**, **GaussianSplats3D (MIT)** ou **SuperSplat viewer de PlayCanvas (MIT)** ; `flutter_gaussian_splatter` (MIT) existe mais est jeune (15 j’aime). Les acquéreurs (futur tunnel A) utilisent la même page.
5. Surfaces et plan : sans LiDAR, l’échelle vient uniquement d’ARKit ; extraction des murs/sol à partir de la scène = recherche appliquée. **Non réaliste en v1-v2.**

**Faisabilité pour nous en v1 : non.** Des dizaines de tranches, une infrastructure GPU, une chaîne de traitement à surveiller, des réglages par type de scène. C’est le cœur de métier de sociétés dédiées (Matterport, Varjo Teleport, Polycam, KIRI, Niantic Scaniverse).

| Critère | Évaluation |
|---|---|
| Compatibilité | iPhone 14 Plus : oui pour la capture (sans LiDAR = qualité moindre sur murs blancs, vitrages, miroirs). Android : à refaire (ARCore). |
| Coût par bien | GPU ≈ 1 à 4 $ (30 à 120 min de L40S/A100 pour une maison, découpée par pièce ; **estimation**) + stockage vidéo source 0,4–1,2 Go + diffusion 10–40 Mo par scène compressée et par visionnage (1 000 vues × 30 Mo ≈ 30 Go ≈ 2,70 $ au-delà du quota). Le coût dominant est l’ingénierie, pas le calcul. |
| Durée de traitement | 20 à 60 min par maison **(estimation)**. |
| Volume | 1080p HEVC ≈ 60 Mo/min, 4K ≈ 170 Mo/min (chiffres Apple) : 7 min ≈ 420 Mo (1080p) à 1,2 Go (4K). Upload sur 4G/5G : plusieurs minutes, reprise indispensable. |
| Vie privée | Les visages, photos de famille, courriers, écrans sont *dans la scène 3D* : il faut flouter chaque image d’entrée avant reconstruction (détection de visages, détection d’objets « cadre photo / document »). Vérifier où tourne le GPU (région UE, contrat de sous-traitance RGPD). |
| Risques qualité (capture amateur) | Mouvements trop rapides (flou), rotations sur place (casse le calcul des poses), pièces sombres, murs unis, fenêtres surexposées, miroirs, portes fermées, personnes qui bougent. Les mêmes vidéos donnent des scènes très inégales. |
| Effort | **30 à 50 tranches** + exploitation (file de jobs, reprises, coûts) ; plusieurs semaines de mise au point de la qualité. |
| Branchement tunnel | V11a-2 / V11a-3 (après certification, pas dans V1–V7). Les pièces de V5c servent de liste de chapitres ; les surfaces restent celles de V5c. |

### Option 2 — Vidéo → 3D via un service tiers (API ou application partenaire)

Même expérience que l’option 1 pour le vendeur et l’acquéreur, mais la reconstruction est achetée.

| Service | Ce qui est vérifié | Limites / incertitudes |
|---|---|---|
| **KIRI Engine API** | API REST (upload vidéo → 3DGS, webhooks, mode test). 1 crédit = 1 $ par scan, recharge minimale 500 crédits, 20 crédits offerts. Vidéo **≤ 1920×1080 et ≤ 3 min**. | API « en phase de test », tarif susceptible d’évoluer. Une maison = 3 à 5 vidéos donc 3 à 5 $. Pas de plan, pas de surfaces, pas de floutage annoncés. Localisation des données et contrat RGPD **(à vérifier)**. |
| **Varjo Teleport** | Plateforme de reconstruction 3DGS dans le cloud, cible explicite « visites 3D immobilières », accepte vidéos ou images, partage par lien, intégration web, export `.ply`, **API développeur annoncée**. Offre grand public ≈ 30 $/mois pour 15 scans, gratuite pour 5 scans. | Tarif API non public, mesures et floutage non documentés **(à vérifier auprès de Varjo)**. Varjo est finlandais (UE) : point favorable pour le RGPD, à confirmer. |
| **Luma AI** | A proposé une API vidéo → 3D à 1 $ par scène. | Luma a **suspendu le traitement des splats** et arrêté *Flythroughs* au 1er janvier 2026 ; l’entreprise s’est recentrée sur la vidéo générative. **Ne pas s’appuyer dessus.** |
| **Polycam** | Upload vidéo (15 s à 30 min selon l’offre) vers photogrammétrie ou splats, offres Pro ≈ 150 $/an, Business ≈ 400 $/an. | Pas d’API publique documentée trouvée **(à vérifier)** : le vendeur devrait utiliser l’app Polycam. |
| **Matterport (groupe CoStar depuis février 2025)** | App Capture gratuite sur iPhone **avec ou sans LiDAR** (sans LiDAR : profondeur estimée par l’IA Cortex ; meilleurs résultats avec LiDAR ou ultra grand-angle) et Android 9+. Capture par **points de vue fixes en panoramique**, pas par vidéo libre. Visite « dollhouse », plan en option. Offre gratuite = 1 espace actif, Starter 9,99 $/mois, Professional 69 $/mois. | **Pas de SDK de capture intégrable** dans notre app trouvé ; les API/SDK développeur (Model API, SDK for Embeds) exigent un **abonnement Enterprise + licence outils développeur**. La liste publique d’appareils compatibles ne mentionne pas l’iPhone 14 (page probablement ancienne, **à vérifier**). CoStar est un concurrent potentiel (portails immobiliers). |

**Ce que fait le vendeur.** Soit il filme dans notre app (KIRI / Teleport via API), soit il installe l’app du partenaire, filme, puis colle un lien de partage dans V11a (Matterport, Polycam, Teleport grand public).

**Faisabilité v1 : non recommandée, mais c’est la bonne voie pour un pilote en v3.** Le parcours « app tierce + lien collé » coûte 3 à 4 tranches (champ lien, validation de domaine, affichage dans une `webview`) ; l’intégration API complète (KIRI / Teleport) coûte **10 à 15 tranches** (upload reprenable, job, webhook, visionneuse, relecture vendeur, floutage en amont).

| Critère | Évaluation |
|---|---|
| Coût par bien | 3 à 5 $ (KIRI) ; ≈ 2 $/scan en grand public Teleport ; Matterport 0 à 69 $/mois selon le nombre d’espaces actifs. Stockage et diffusion chez le partenaire (ou chez nous si export). |
| Durée | Quelques minutes à une heure **(non documenté précisément)**. |
| Vie privée | Les images partent chez un tiers (hors UE pour plusieurs) : contrat de sous-traitance, information du vendeur, floutage avant envoi si possible. |
| Qualité | Meilleure que notre pipeline maison au départ, mais même sensibilité à la façon de filmer. Surfaces : non fournies (sauf Matterport, avec ses propres réserves). |
| Dépendance | Forte (prix, arrêt de service : l’exemple Luma le montre). Prévoir l’export des scènes (`.ply`/`.spz`) et notre propre visionneuse. |

### Option 3 — Visite virtuelle 360° par panoramas (points de vue fixes reliés)

**Ce que fait le vendeur.** Dans chaque pièce, il se place au centre et tourne sur lui-même en suivant une cible à l’écran (12 à 24 prises, ultra grand-angle). 1 à 3 points de vue par pièce.

**Résultat.** Une visite « à la Google Street View » : on regarde autour de soi dans chaque pièce, on saute de pièce en pièce par la liste (ou par des flèches si on relie les points de vue). C’est ce que la maquette V11a-3 montre réellement (« 360° · Glissez pour regarder autour »).

**Approche technique.**
- Capture guidée : `camera` (BSD-3) + gyroscope `sensors_plus` (BSD-3) pour la cible de visée. Apple ne fournit pas d’API panorama 360° ; le mode Pano natif est un bandeau horizontal, inaccessible depuis une app.
- Assemblage : sur le serveur, OpenCV Stitcher (Apache-2.0 depuis OpenCV 4.5) dans un worker (pas en Edge Function) ; ou sur l’appareil via `opencv_dart` (Apache-2.0, binaires lourds, **à vérifier**). Hugin est GPL : exclu.
- Visionneuse : `panorama_viewer` (Apache-2.0) dans l’app ; Pannellum ou Photo Sphere Viewer (MIT) pour le web.
- Alternative « partenaire » : app Matterport (capture par panoramas, y compris sans LiDAR) + lien intégré.

**Faisabilité v1 : non.** Un panorama tenu à la main présente des raccords visibles (parallaxe), le sol et le plafond manquent souvent ; obtenir un rendu propre est un vrai chantier. **12 à 18 tranches** (capture guidée, upload, worker d’assemblage, visionneuse, navigation entre pièces).

| Critère | Évaluation |
|---|---|
| Compatibilité | Tous les iPhone et Android avec gyroscope. |
| Coût | Faible : 15 à 25 Mo de photos par pièce, assemblage CPU de quelques secondes à une minute par panorama (centimes par bien). |
| Vie privée | Le vendeur est souvent dans le reflet des miroirs ; floutage des visages sur chaque prise. |
| Qualité | Moyenne en capture amateur ; correcte avec une tête panoramique ou une caméra 360° (Insta360…) que le vendeur n’a pas. |

### Option 4 — Relevé des surfaces à la caméra (AR), avec ou sans LiDAR (carte V5 « Scanner avec la caméra », maquette V5b)

Cette option répond à la question des **surfaces**, pas à celle de la visite. C’est ce que promet V5 (« Surfaces, volumes et revêtements détectés pendant que vous filmez chaque pièce à 360° »).

- **Avec LiDAR (iPhone Pro 12 et suivants, iPad Pro) : Apple RoomPlan.** Murs, portes, fenêtres, meubles, export USDZ, très bonne précision. Plugins MIT `roomplan_flutter` (0.2.1) et `roomplan` (0.3.1), jeunes et peu utilisés (à auditer). **Exclu sur l’iPhone 14 Plus** ; Apple ne propose aucune API de scan de pièce sans LiDAR.
- **Sans LiDAR : relevé « coins au sol » avec ARKit**, comme l’app Mesures d’Apple ou magicplan. Le vendeur vise chaque coin de la pièce au sol ; on calcule le polygone, la surface au sol et, en visant le plafond, la hauteur sous plafond. Plugin `arkit_plugin` (MIT, iOS, à jour en août 2026 : plans, *hit tests*). Android : ARCore (`ar_flutter_plugin` MIT mais non maintenu depuis 2022 ; `ar_flutter_plugin_2` très jeune).
- Précision sans LiDAR : erreur de quelques pourcents dans de bonnes conditions, nettement plus sur sols unis, faible lumière, grandes pièces ou pièces en L **(ordre de grandeur, non mesuré par nous)**. La détection de plans sans LiDAR est sensiblement moins fiable (rebords blancs, surfaces peu texturées).

**Faisabilité v1 : possible mais pas prioritaire.** **10 à 14 tranches** (vue AR native, assistant coins, calcul et contrôle de cohérence, écriture `rooms.area_m2` / `ceiling_height_m` / `scan_data`, `source = 'scan'`, provenance « Mesures estimatives », tests). RoomPlan pour les appareils LiDAR : **+4 à 6 tranches**.

| Critère | Évaluation |
|---|---|
| Coût | Nul côté serveur (tout sur l’appareil). |
| Juridique | Pour un lot de copropriété, la surface Carrez engage le vendeur (action en diminution de prix si l’écart dépasse 5 %) : le téléphone ne remplace pas un mesurage ; la note V5 « Les mesures réalisées au téléphone sont estimatives » doit rester, et l’expert vérifie. |
| Valeur | Moyenne : la saisie manuelle de V5c fonctionne déjà, et un plan photographié donne souvent de meilleurs chiffres. |

### Option 5 — Visite vidéo guidée pièce par pièce, sans reconstruction 3D

**Ce que fait le vendeur.** Même écran que la maquette V11a-2 (pièce en cours, conseils, indicateurs de qualité, « Pièce suivante »), mais il filme **20 à 45 s par pièce**, en un plan lent et continu.

**Résultat.** Une « visite vidéo » découpée en chapitres par pièce (liste des pièces de V5c), lisible dans l’app et sur le web (`video_player`, BSD-3), avec une image de couverture par pièce. Le serveur extrait les **meilleures images fixes** de chaque vidéo pour proposer des photos d’annonce. Pas de 360° interactif, pas de mesures.

**Approche technique.**
- Capture : `camera` (BSD-3) avec superposition de guidage ; indicateurs **sur l’appareil** : stabilité et vitesse de rotation par le gyroscope (`sensors_plus`), luminosité par l’exposition ou la luminance des images. Conseils vocaux : phrases préparées lues par la synthèse vocale existante (`agent-speech`), **pas** d’analyse IA en temps réel (latence et coût).
- Compression avant envoi : `video_compress` (MIT, AVFoundation sur iOS) en 720p/1080p HEVC ; pas de FFmpeg (LGPL).
- Upload : une vidéo par pièce (≈ 20 à 45 Mo en 1080p HEVC), donc **sous la limite de 50 Mo** même en offre gratuite ; upload standard avec reprise par pièce.
- Extraction d’images et floutage des visages : worker (FFmpeg côté serveur : la contrainte LGPL ne vise que les dépendances Dart, **à confirmer** pour un usage serveur) ou, plus simple, extraction de 3 à 5 images sur l’appareil (`video_thumbnail`-like natif AVAssetImageGenerator) puis analyse comme l’option 6.

**Faisabilité : bonne en v2. 8 à 12 tranches** (écran de capture guidée, chapitres, compression, upload, lecture, extraction d’images, floutage, intégration V11a).

| Critère | Évaluation |
|---|---|
| Compatibilité | Tous appareils (aucune exigence AR). |
| Coût par bien | 9 pièces × ~35 Mo ≈ 300 Mo stockés (≈ 0,006 $/mois) ; diffusion en 720p ≈ 15 Mo par pièce et par visionnage. Analyse IA des images extraites : quelques centimes. |
| Temps | Disponible dès l’upload ; images extraites en 1 à 2 min. |
| Vie privée | Visages et voix : **couper la piste audio** par défaut (conversations, noms prononcés) ; flouter les visages image par image coûte plus cher que pour des photos (traitement serveur), ou on demande au vendeur de filmer une maison vide d’occupants et on modère avant publication. |
| Qualité | Une vidéo tenue à la main est plus tolérante qu’un modèle 3D : un défaut gâche une pièce, pas toute la visite. Stabilisation iOS native active. |

### Option 6 — Photos guidées pièce par pièce, avec contrôle qualité et IA (recommandée pour v1)

**Ce que fait le vendeur.** Dans V5c (ou un écran V5b simplifié « Photos de vos pièces »), pour chaque pièce : 2 à 6 photos, avec conseils (« Placez-vous dans un angle, téléphone à hauteur de poitrine, 0,5× », « Allumez les lumières, ouvrez les rideaux »). Chaque photo est vérifiée en quelques secondes (« Photo un peu sombre », « Téléphone penché : redressez », « Un visage a été flouté »). L’app **propose** de compléter la ligne de la pièce (« Cuisine · Carrelage · Double vitrage ? ») ; le vendeur confirme.

**Résultat.** Pour l’expert : 20 à 40 photos classées par pièce dans le dossier, utiles pour une pré-analyse à distance (état, finitions, défauts visibles) avant la visite de certification. Pour les acquéreurs (V11a, après certification) : les photos d’annonce sont déjà là, classées, floutées, avec une couverture proposée. C’est aussi la base du « Prendre mes photos avec l’assistant » de V11 (EPIC-08).

**Approche technique.**
- **Capture** : deux variantes.
  - `image_picker` en mode caméra (Apache/BSD, déjà dans le projet) : interface photo système d’iOS, objectif 0,5× disponible, HDR natif, mais aucune superposition de guidage. Le plus rapide à livrer.
  - `camera` (BSD-3) : écran personnalisé avec grille, niveau à bulle (`sensors_plus`), conseils. Le choix de l’ultra grand-angle via le plugin est **à vérifier** (iOS l’expose comme une caméra séparée selon les versions de `camera_avfoundation`).
- **Contrôles sur l’appareil (gratuits, immédiats)** : inclinaison (accéléromètre au moment de la prise), luminosité moyenne et netteté (variance du laplacien) via le paquet `image` déjà présent, dans un isolat ; orientation paysage conseillée ; redimensionnement à 2048 px JPEG (≈ 0,5–1 Mo au lieu de 3–5 Mo en HEIC/JPEG 12 Mpx).
- **Floutage des visages sur l’appareil** avant upload : Apple Vision (`VNDetectFaceRectanglesRequest`, framework système, aucune licence tierce) via un petit canal natif, ou `google_mlkit_face_detection` (plugin MIT, SDK ML Kit sous conditions Google, multiplateforme). Les visages ne quittent jamais le téléphone.
- **Analyse serveur via OpenRouter** (Edge Function `analyze-room-photo`, modèle configurable par secret, comme EPIC-06) : sortie JSON structurée, sans chiffres :
  - type de pièce (parmi les puces de V5c), revêtement de sol (liste V5b/V5c), vitrage si visible, éléments notables (cheminée, poutres, verrière) ;
  - qualité : trop sombre, surexposé, flou, encombré, personne visible, **objets personnels à masquer** (cadres photo, courrier, écrans, plaques d’immatriculation par la fenêtre) avec boîtes englobantes (les modèles Gemini savent renvoyer des boîtes **à vérifier sur le modèle retenu**) ;
  - suggestion de photo de couverture.
  - Coût : une image de 1024 px ≈ 1 000 à 1 500 jetons ; à 0,30 $/M jetons d’entrée (Gemini 3.5 Flash-Lite sur OpenRouter), ≈ 0,0005 $ par photo, soit **moins de 0,05 $ par bien** même avec un modèle 10 fois plus cher.
- **Stockage** : bucket privé (ex. `property-media`, `<user id>/<property id>/rooms/<room id>/…`), même verrou RLS que `property-documents` (écriture seulement en brouillon). Table proposée `room_photos` (id, property_id, room_id, storage_path, width, height, sort_order, is_cover, quality jsonb, ai_suggestions jsonb, faces_blurred boolean, taken_at) ; `rooms.photos_count` mis à jour.
- **Règles IA du projet respectées** : l’IA classe et signale ; toute valeur proposée (revêtement, vitrage, type) est affichée comme suggestion, confirmée par le vendeur, avec une provenance dédiée (proposée par l’IA, puis « Déclaré » une fois confirmée). Aucune surface déduite d’une photo.

**Faisabilité v1 : oui.** Version de base (photo par pièce, sans IA) : **3 à 4 tranches**. Version complète (contrôles sur l’appareil, floutage, analyse OpenRouter, suggestions dans la fiche pièce) : **+6 à 8 tranches**, soit **9 à 12 tranches** au total.

| Critère | Évaluation |
|---|---|
| Compatibilité | iPhone 14 Plus : oui. Android : oui (ML Kit pour le floutage, `image_picker`/`camera`). |
| Coût par bien | Stockage 15–40 Mo (négligeable) ; IA < 0,05 $. |
| Temps | Contrôles locaux instantanés ; analyse serveur 2 à 6 s par photo, en arrière-plan (le vendeur continue). |
| Vie privée | Visages floutés avant upload ; objets personnels signalés pour que le vendeur reprenne la photo ; images transmises au fournisseur du modèle via OpenRouter : choisir un fournisseur sans conservation des données et informer le vendeur (même logique que le consentement vocal). Sécurité : une annonce avec photos + adresse exacte renseigne les cambrioleurs ; conseiller de ranger objets de valeur, alarme, coffre. |
| Qualité | Photos amateur : défauts prévisibles (penchées, sombres, trop serrées) ; les contrôles et la reprise immédiate en corrigent l’essentiel. La retouche IA et le home staging virtuel restent des options V11 (à signaler comme « image retouchée / aménagement virtuel » pour éviter une pratique commerciale trompeuse). |

### Option 6 bis — Photographier un plan existant (V5 « Importer ou photographier un plan »)

Pas une capture du bien mais le meilleur rapport valeur/effort pour **les surfaces** : le vendeur photographie le plan (scanner VisionKit de V7 déjà intégré) ; une Edge Function envoie l’image à un modèle de vision via OpenRouter qui **extrait** la liste des pièces et les surfaces *écrites sur le plan* ; V5c est pré-rempli avec la provenance « Extrait d’un document » (`rooms.source = 'plan'`) et le vendeur vérifie chaque ligne. Conforme à la règle « l’IA extrait, n’invente pas » (contrôle : la somme doit correspondre au total imprimé s’il existe ; une surface absente du plan reste vide). **4 à 6 tranches.** Coût : centimes.

### Option 7 — Une photo simple par pièce pendant le tunnel (la plus simple)

**Ce que fait le vendeur.** Dans la fiche d’une pièce (V5c), bouton « Ajouter une photo » : appareil photo ou photothèque (`image_picker`), 1 à 3 photos, sans conseil ni contrôle.

**Résultat.** L’expert voit chaque pièce ; les photos peuvent être reprises dans l’annonce V11a.

**Faisabilité : immédiate. 3 à 4 tranches** (migration table + bucket + RLS ; ajout/suppression/aperçu dans la fiche pièce ; vignettes dans le récapitulatif V5c et l’aperçu V8). Aucun coût notable. Pas de floutage : à réserver aux tests internes ou à compléter tout de suite par l’option 6.

---

## 3. Synthèse comparative

| # | Option | iPhone 14 Plus | Android | Coût / bien (hors dev) | Délai résultat | Effort (tranches) | Risque qualité | v1 ? |
|---|---|---|---|---|---|---|---|---|
| 1 | Vidéo → 3D, pipeline maison | Capture oui, échelle via ARKit, surfaces non fiables | À refaire | 1–4 $ GPU + diffusion | 20–60 min | 30–50 + exploitation | Élevé | Non |
| 2 | Vidéo → 3D via tiers (KIRI, Teleport ; Matterport en panoramas) | Oui (selon le service) | Oui (Matterport) | 2–5 $ (ou abonnement) | Minutes à 1 h | 3–4 (lien) / 10–15 (API) | Moyen-élevé + dépendance | Non (pilote v3) |
| 3 | Panoramas 360° maison | Oui | Oui | Centimes | 1–2 min | 12–18 | Moyen-élevé | Non |
| 4 | Relevé AR des surfaces | Sans LiDAR : coins au sol (approximatif) ; RoomPlan exclu | ARCore (plugins faibles) | 0 | Immédiat | 10–14 (+4–6 RoomPlan) | Moyen | Non (v2, facultatif) |
| 5 | Vidéo par pièce, sans 3D | Oui | Oui | < 0,10 $ | Immédiat | 8–12 | Faible-moyen | Non (v2) |
| 6 | Photos guidées + IA | Oui | Oui | < 0,05 $ | Secondes | 9–12 | Faible | **Oui** |
| 6 bis | Plan photographié → pièces | Oui | Oui | Centimes | Secondes | 4–6 | Faible (vérification vendeur) | **Oui** |
| 7 | Photo simple par pièce | Oui | Oui | ≈ 0 | Immédiat | 3–4 | Faible (sans contrôle) | Oui (socle de 6) |

---

## 4. Branchement dans le parcours existant

| Écran | Aujourd’hui | Proposition |
|---|---|---|
| **V5 · Méthode de relevé** | Seule « Saisir manuellement » est active ; plan = upload simple ; caméra masquée ou « Bientôt » | v1 : activer « Importer ou photographier un plan » avec extraction (6 bis). La carte « Scanner avec la caméra » reste « Bientôt » tant que l’option 4 n’existe pas ; ne pas promettre « surfaces détectées pendant que vous filmez ». Les photos ne sont pas une « méthode de relevé » : elles s’ajoutent quelle que soit la méthode. |
| **V5b · Scan pièce par pièce** | Écran caméra différé (AR + photos + revêtement) | v1 : réutiliser sa structure pour un écran « Photos de la pièce » (pièce N sur M, `Photos 2/4`, revêtement et vitrage pré-proposés, « Valider et passer à la pièce suivante ») **sans** puces de mesure `38,5 m²` / `HSP`. v2 : ajouter le relevé AR (option 4) dans le même écran. |
| **V5c · Récapitulatif des surfaces** | Tableau des pièces, édition dans une feuille | Nombre de photos et vignette par ligne ; « Ajouter des photos » dans la feuille d’édition ; badge `Photos 18` dans l’en-tête. `rooms.photos_count` est déjà en base. |
| **V7 · Documents** | Scan VisionKit, type `plan` existant | Un plan déjà déposé en V5 apparaît en V7 (type `plan`) et inversement ; pas de double saisie. |
| **V8 · Aperçu des données** | Résumé du dossier | Section « Photos » (nombre par pièce). |
| **Expert (back-office, EPIC-12)** | — | Galerie par pièce dans le dossier ; utile pour préparer la visite et le « Constat de visite » de V9b. |
| **V11a · Mise en ligne (EPIC-08)** | `listing_photos` + bucket `listing-media` prévus ; carte « Visite virtuelle 360° » masquée | Proposer de copier les photos du tunnel vers l’annonce (avec choix du vendeur et couverture suggérée), puis compléter. La carte « Visite virtuelle » reste masquée jusqu’à v2 (vidéo par pièce : renommer « Visite vidéo ») ou v3 (3D). |
| **V11a-3** | Maquette « Générée par l’IA · À valider », « Surfaces mesurées 115 m² » | Quand une 3D existe : afficher les surfaces **de V5c** (provenance indiquée), jamais « mesurées » depuis la vidéo ; garder « Flouter visages et photos personnelles » (appliqué par défaut). |

Verrou : les médias du tunnel suivent la règle des documents (écriture autorisée seulement en brouillon) ; les médias d’annonce suivent l’étape de vente (EPIC-08).

---

## 5. Parcours recommandé

### v1 (tunnel V1–V7, maintenant) — « Photos guidées + plan lu par l’IA »
1. **Socle photo par pièce** (option 7) : migration `room_photos` + bucket privé + RLS verrou ; ajout depuis la fiche pièce V5c ; vignettes. *3–4 tranches.*
2. **Contrôle qualité sur l’appareil + floutage des visages** (Apple Vision ou ML Kit, à trancher) + redimensionnement. *3 tranches.*
3. **Edge Function `analyze-room-photo`** (OpenRouter, sortie JSON, modèle par secret) + suggestions confirmables (type, revêtement, vitrage, objets à masquer, couverture). *3–4 tranches.*
4. **Écran « Photos de la pièce »** dérivé de V5b (enchaînement pièce par pièce). *2 tranches.*
5. **Plan photographié → pré-remplissage V5c** (option 6 bis). *4–6 tranches.*

Total ≈ **15 à 19 tranches**, entièrement compatible iPhone 14 Plus, coût de fonctionnement de l’ordre de quelques centimes par bien, aucune nouvelle dépendance hors licences autorisées (sauf si ML Kit est retenu : conditions Google à accepter).

### v2 (avec l’annonce V11a, EPIC-08) — « Visite vidéo + mesures facultatives »
- Visite vidéo par pièce (option 5), présentée comme « Visite vidéo » (pas « 360° »), audio coupé par défaut, extraction d’images pour l’annonce.
- Relevé AR facultatif dans V5b (option 4) : coins au sol sans LiDAR, RoomPlan si l’appareil a un LiDAR ; toujours « Mesures estimatives », vérifiées par l’expert.
- Retouche photo IA (luminosité, redressement) avec mention « photo retouchée » ; home staging virtuel signalé comme tel.

### v3 (après validation commerciale) — « Pilote visite 3D »
- Tester **2 à 3 services tiers** (Varjo Teleport, KIRI API ; Matterport en lien collé) sur 5 à 10 biens réels filmés par des vendeurs non formés ; critères : rendu sur mobile, taux d’échec, délai, coût réel, région d’hébergement, contrat RGPD, export de la scène.
- Construire V11a-2 (capture guidée, déjà prototypée en v2) + V11a-3 (visionneuse web MIT dans une `webview`) au-dessus du service retenu.
- Ne construire un pipeline maison (option 1) que si le volume justifie l’équipe et l’infrastructure GPU, et seulement sur des briques Apache/BSD/MIT (gsplat, GLOMAP, SPZ).

---

## 6. Questions ouvertes pour le porteur de projet

1. **Objectif principal de la capture en v1 ?**
   a) aider l’expert à préparer la certification (photos de constat, tout le bien, y compris défauts) ;
   b) préparer l’annonce (photos flatteuses, sélectionnées) ;
   c) les deux, avec deux usages distincts des mêmes photos (recommandé : on capture une fois, le vendeur choisit plus tard ce qui va dans l’annonce).
2. **Où placer la capture photo ?**
   a) dans V5c, depuis la fiche de chaque pièce (le plus simple) ;
   b) un écran dédié pièce par pièce dérivé de V5b (le plus guidé) ;
   c) seulement après certification, dans V11a (tunnel plus court, mais l’expert n’a pas les photos).
3. **Photos obligatoires pour envoyer le dossier ?** a) non (recommandé en v1, comme les diagnostics) ; b) au moins une par pièce principale ; c) un minimum global (ex. 8).
4. **Floutage des visages** : a) Apple Vision (iOS seulement, aucune licence tierce ; refaire pour Android) ; b) Google ML Kit (iOS + Android, plugin MIT, conditions Google à accepter comme pour Mapbox) ; c) pas de floutage automatique en v1, consigne « personne dans le champ » + contrôle IA.
5. **Envoi des photos à un modèle de vision via OpenRouter** : acceptez-vous que les photos de l’intérieur soient transmises à un fournisseur de modèle (sans conservation, à configurer) ? a) oui, avec information du vendeur à la première utilisation (comme le consentement micro) ; b) seulement après floutage sur l’appareil ; c) non : contrôles locaux uniquement en v1.
6. **Plan photographié lu par l’IA (6 bis) en v1 ?** a) oui (recommandé) ; b) plus tard, upload simple pour l’expert comme prévu.
7. **Carte V5 « Scanner avec la caméra »** : a) la garder « Bientôt » ; b) la masquer ; c) la transformer en « Photographier mes pièces » (attention : elle ne relèverait plus de surfaces).
8. **Visite virtuelle dans l’offre commerciale** (V10, V11 promettent « visite 360° », « vidéo immersive IA ») : a) retirer la promesse jusqu’à v3 ; b) la remplacer par « visite vidéo » en v2 ; c) passer par le shooting photo + vidéo partenaire (350 € TTC, maquette V11) pour les biens qui la veulent dès maintenant.
9. **Pilote 3D en v3** : a) service tiers d’abord (recommandé) ; b) pipeline maison ; c) abandon de la 3D au profit de la vidéo. Et quels services contacter (Varjo Teleport pour l’API et l’hébergement UE, KIRI, Matterport/CoStar malgré le risque concurrentiel) ?
10. **Passage à Supabase Pro** : nécessaire dès qu’on stocke des vidéos de plus de 50 Mo (option 1/2 surtout) ; à prévoir pour v2-v3, pas pour v1.

---

## 7. Points incertains à lever avant de coder

- Choix de l’objectif ultra grand-angle avec le plugin `camera` sur iOS.
- Capacité du modèle de vision retenu (Gemini 3.5 Flash-Lite ou autre) à renvoyer des boîtes englobantes fiables pour les objets personnels ; benchmark sur 30 photos réelles, comme pour la voix.
- Fournisseurs OpenRouter sans conservation des données pour les images, et région de traitement.
- Tarifs et contrats API de Varjo Teleport et Matterport ; pérennité et localisation de KIRI ; licence exacte de VGGT.
- Utilisation de FFmpeg (LGPL) côté serveur uniquement : compatible avec la politique de licences (qui ne vise que les dépendances Dart) ?
- Précision réelle du relevé ARKit sans LiDAR sur l’iPhone 14 Plus : à mesurer sur 5 pièces connues avant de promettre quoi que ce soit.

---

## Sources

- Supabase : [limites de taille des fichiers Storage](https://supabase.com/docs/guides/storage/uploads/file-limits), [limites des Edge Functions](https://supabase.com/docs/guides/functions/limits), [tarifs Storage (synthèse 2026)](https://makerkit.dev/blog/saas/supabase-pricing).
- Apple RoomPlan et LiDAR : [forum Apple « RoomPlan sans LiDAR »](https://developer.apple.com/forums/thread/751207), [forum Apple n° 776280](https://developer.apple.com/forums/thread/776280), [plugin `roomplan`](https://pub.dev/packages/roomplan) ; ARKit sans LiDAR : [Nomtek, plan de pièce avec ARKit](https://www.nomtek.com/blog/getting-a-room-plan-with-arkit), [Niantic, détection de plans](https://community.nianticspatial.com/t/plane-detection-does-not-recognise-some-window-sills/4403).
- Matterport : [appareils compatibles](https://matterport.com/compatible-mobile-devices), [app Capture sur iPhone (Geo Week News)](https://www.geoweeknews.com/?p=25171), [outils développeur](https://matterport.com/blog/announcing-general-availability-matterport-developer-tools), [accord SDK](https://matterport.com/legal/sdk-agreement/), [rachat par CoStar](https://onlinemarketplaces.com/articles/costar-completes-1-6-billion-matterport-acquisition), [tarifs (agrégateur)](https://toolradar.com/tools/matterport/pricing).
- Luma : [API vidéo → 3D](https://radiancefields.com/luma-ai-announces-video-to-3d-api), [arrêt de Flythroughs au 1er janvier 2026](https://radiancefields.com/luma-ai-to-sunset-flythroughs-on-january-1-2026).
- KIRI Engine : [page API](https://kiriengine.app/api), [documentation](https://docs.kiriengine.app/), [tarifs](https://kiriengine.app/pricing).
- Varjo Teleport : [visites 3D immobilières](https://get.teleport.varjo.com/product-pages/3d-property-tours), [lancement et tarifs (Road to VR)](https://roadtovr.com/varjo-teleport-3d-model-scanning-app-release/).
- Polycam : [création depuis images et vidéos](https://learn.poly.cam/hc/en-us/articles/30549121659412-How-to-Create-Photogrammetry-and-Gaussian-splats-from-Existing-Images-and-Videos), [comparatif 2026](https://www.thefuture3d.com/blog/gaussian-splatting-software-tools-compared-2026).
- Reconstruction ouverte : [gsplat (Apache-2.0)](https://arxiv.org/html/2409.06765v1), [nerfstudio Splatfacto](https://radiancefields.com/nerfstudio-1-0-and-splatfacto-released), [VGGT](https://openaccess.thecvf.com/content/CVPR2025/papers/Wang_VGGT_Visual_Geometry_Grounded_Transformer_CVPR_2025_paper.pdf), [revue DUSt3R → VGGT](https://arxiv.org/pdf/2507.08448) ; licences vérifiées sur GitHub (GLOMAP BSD-3, SPZ MIT ; 3DGS Inria, MASt3R et VGGT sous licences propres) et npm (Spark, GaussianSplats3D, SuperSplat viewer, Pannellum, Photo Sphere Viewer : MIT).
- GPU : [tarifs Modal](https://modal.com/pricing).
- OpenRouter : [Gemini 3.5 Flash-Lite, tarifs](https://pricepertoken.com/pricing-page/model/google-gemini-3.5-flash-lite).
- Plugins Flutter (licences relevées sur pub.dev le 2026-10-02) : `camera` BSD-3, `image_picker` Apache-2.0/BSD-3, `video_player` BSD-3, `webview_flutter` BSD-3, `sensors_plus` BSD-3, `panorama_viewer` Apache-2.0, `opencv_dart` Apache-2.0, `arkit_plugin` MIT, `ar_flutter_plugin` MIT (non maintenu depuis 2022), `roomplan` / `roomplan_flutter` MIT, `google_mlkit_face_detection` MIT (SDK ML Kit sous conditions Google), `video_compress` MIT, `tus_client_dart` MIT (2023), `flutter_gaussian_splatter` MIT, `model_viewer_plus` Apache-2.0 ; `ffmpeg_kit_flutter(_new)` **LGPL-3.0, exclu**.
- Volumes vidéo iPhone (HEVC 1080p30 ≈ 60 Mo/min, 4K30 ≈ 170 Mo/min) : réglages Appareil photo d’iOS (Réglages > Appareil photo > Enregistrement vidéo).

## Arbitrages du porteur de projet (2026-10-02)
- Q1 : **les deux usages** (expert + annonce) avec une seule capture ; les photos doivent être assez documentées pour l'analyse de l'expert. L'outil doit aussi être intégré au parcours vendeur **au moment de la mise en vente** (V11a) pour ceux qui ne l'ont pas utilisé dans le tunnel.
- Q2 : capture **depuis chaque pièce dans V5c**.
- Q3 : **au moins une photo par pièce principale** pour envoyer le dossier.
- Q5 : **IA de vision via OpenRouter avec consentement** au premier usage.
- Q4 : **pas de floutage automatique en v1** (au backlog, après les tests) : consigne « personne dans le champ » à l’écran, l’IA signale les personnes, la photo est à reprendre ou supprimer.
- Q6 : **lecture d’un plan en v1** (pièces et surfaces imprimées seulement, validation ligne par ligne, provenance « Extrait d’un document »).
- Q7 : **carte « Scanner avec la caméra » retirée** pour l’instant.
- Questions 8–10 : à trancher. Mise en œuvre : [Photos du bien](2026-10-02-photos-du-bien.md) (EPIC-15).

- Q8 (2026-10-03) : promesse « visite 360° / vidéo immersive » **retirée jusqu'à la v3**.
