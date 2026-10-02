# EPIC-05 · Estimation non certifiée (« Tendance IA ») — étude & conception

Statut : proposition (aucun code écrit). Rédigé le 2026-10-01 à partir de `CLAUDE.md`, `docs/plans/2026-09-30-tunnel-vendeur*.md` (spec §2 V8/V8b, §3, §4), des migrations `supabase/migrations/*`, du code V8 (`lib/seller_tunnel/steps/submitted/…`, `AiEstimateCard`) et des maquettes `AttenteExpert.dc.html` (V8) et `SyntheseMarche.dc.html` (V8b).

Objectif du porteur de projet : un **simulateur de tendance de prix** qui donne une **première estimation NON certifiée** en croisant les ventes notariées **DVF** et la **tendance du prix au m²**. **Pas d’annonces en v1.** L’IA (Claude via OpenRouter) ne sert qu’à **rédiger l’explication en français** à partir de chiffres calculés ; elle n’invente aucun chiffre.

**Décisions du porteur de projet (2026-10-01), intégrées ci-dessous :**
1. L’estimation est calculée **une seule fois, à l’envoi du dossier**, et **jamais recalculée** après des modifications (l’expert certifie ensuite).
2. Les ventes comparables sont affichées **avec le nom de la rue, sans le numéro**.
3. **Moins de 5 ventes comparables → pas d’estimation**, message « l’expert s’en charge ».
4. Méthode validée : comparables DVF du même type, rayon élargi **500 m → 1 km → 2 km → commune**, **3 à 5 dernières années**, surface habitable **± 30 %**, valeurs aberrantes écartées (ventes multi-lots, dépendances seules, €/m² extrêmes), **médiane et quartiles pondérés** du €/m² (poids proximité et ancienneté), **courbe semestrielle** du €/m² médian sur 5 ans avec **projection des ventes passées à aujourd’hui**, **ajustements simples et visibles** (part des annexes, grand terrain, année de construction, piscine / garage), **indice de confiance** ; l’IA rédige seulement l’explication.

---

## 1. Accès aux données DVF en 2026 — relevé fait au `curl` le 2026-10-01

| Accès | URL testée | Résultat | Fraîcheur | Licence / conditions | Verdict |
|---|---|---|---|---|---|
| **geo-dvf (Etalab), fichiers CSV par commune** | `https://files.data.gouv.fr/geo-dvf/latest/csv/2025/communes/69/69043.csv` | **200** après redirection 302 vers `https://geo-dvf.s3.sbg.io.cloud.ovh.net/latest/csv/…` (S3 OVH ; `ETag` + `Last-Modified` fournis). Chaponost 2025 : 64 Ko, 366 lignes. | Millésimes **2021 → 2025** (`latest/csv/2026/` vide). Fichiers du **18/05/2026** ; ventes jusqu’au **29/12/2025**. Mise à jour semestrielle (avril / octobre côté DGFiP ; Etalab republie ~1 mois après). Seules archives : `2025-12/` et `latest/`. | **Licence Ouverte 2.0** (`lov2` sur data.gouv) + CGU DGFiP (voir ci-dessous). | **Source principale v1** : ventes individuelles géolocalisées (lat/lng), légères, sans clé. |
| geo-dvf, fichier par département | `…/latest/csv/2025/departements/69.csv.gz` | 200, **2,1 Mo gz/an** (Paris 75 : 2,0 Mo) | idem | idem | Trop lourd à parser dans une Edge Function (limite CPU) ; inutile si on charge par commune. |
| geo-dvf, fichier national | `static.data.gouv.fr/…/dvf.csv.gz` (ressource « DVF janvier 2021 – décembre 2025 », 17/07/2026) | — | idem | idem | Hors périmètre (ingestion batch). |
| **Statistiques DVF (data.gouv.fr) via l’API tabulaire** | `https://tabular-api.data.gouv.fr/api/resources/851d342f-9c96-41c1-924a-11a7a7aae8a6/data/?code_geo__exact=69043` (totaux) et `…/03fba98d-885b-43c0-8986-d299cabc29da/data/?code_geo__exact=69043&annee_mois__sort=desc` (mensuel) | **200 JSON**, CORS `*`, `cache-control: public`. Échelles : nation, département, EPCI, **commune**, **section cadastrale** (`code_geo=69043000AI` fonctionne). Champs : `nb_ventes_*`, `moy_prix_m2_*`, `med_prix_m2_*` pour `maison`, `appartement`, `apt_maison`, `local` ; mensuel `annee_mois` jusqu’à **2025-12**. | Publié le **17/07/2026** (données 2021-01 → 2025-12). | Licence Ouverte 2.0. Pas d’en-tête de quota renvoyé ; limite documentée par data.gouv par IP (à revérifier, on reste à quelques appels par estimation). | **Source secondaire** : tendance lissée (EPCI/département) et repli quand la commune a trop peu de ventes. Méthode Etalab : ventes, VEFA, adjudications, **mutations d’un seul bien**, prix/m² ≤ 100 k€. |
| DGFiP « Demandes de valeurs foncières » (brut) | `https://www.data.gouv.fr/api/1/datasets/demandes-de-valeurs-foncieres/` | 200. Fichiers `.txt.zip` annuels 2021–2025 (65–87 Mo) mis à jour le **07/04/2026** ; prochaine mise à jour **octobre 2026**. | semestrielle | `lov2` + **CGU** : pas de ré-identification des personnes, **pas d’indexation par les moteurs de recherche**. Hors Alsace, Moselle, Mayotte. | Pas d’usage direct (geo-dvf en est la version géolocalisée). |
| API DVF Etalab de l’app « DVF » | `https://app.dvf.etalab.gouv.fr/api/mutations3/69043/000AI` | 200 JSON (118 mutations de la section AI, 2021–2025, tout en chaînes : `"165000.0"`, `"None"`, `"nan"`). | idem geo-dvf | API **non documentée** servant le site ; aucun engagement de stabilité. | À ne pas utiliser (contrat implicite). |
| Cerema « API Données foncières » (DVF+ open data) | `https://apidf-preprod.cerema.fr/dvf_opendata/mutations/?code_insee=69043` | **503** (Service Unavailable) au moment du test ; racine → `/swagger` (503 aussi). `apidf.cerema.fr` ne résout pas. | — | Licence Ouverte pour DVF+ open data | Non fiable aujourd’hui ; garder comme piste future (DVF+ = mutations retraitées). |
| api.cquest.org/dvf | `https://api.cquest.org/dvf?code_commune=69043` | **502 Bad Gateway** | — | — | Abandonné. |
| « API DVF » officielle | `data.gouv.fr/api/1/dataservices/?q=dvf` | Aucune API nationale référencée (seulement des API locales Grand Poitiers, Côtes-d’Armor). | — | — | N’existe pas. |
| Référentiel communes (rayon) | `https://geo.api.gouv.fr/communes?fields=code,centre,codeDepartement,population&format=json` | 200, **34 969 communes**, 4,7 Mo, centres lat/lng. | — | Licence Ouverte | Chargé une fois en base pour trouver les communes voisines. (Les arrondissements Paris/Lyon/Marseille demandent `type=arrondissement-municipal` ; geo-dvf et la BAN utilisent les codes d’arrondissement, ex. 69381.) |

Format d’une ligne geo-dvf (en-tête réel) : `id_mutation, date_mutation, numero_disposition, nature_mutation, valeur_fonciere, adresse_*, code_postal, code_commune, nom_commune, code_departement, ancien_code_commune, ancien_nom_commune, id_parcelle, ancien_id_parcelle, numero_volume, lot1_numero … lot5_surface_carrez, nombre_lots, code_type_local, type_local, surface_reelle_bati, nombre_pieces_principales, code_nature_culture, nature_culture, code_nature_culture_speciale, nature_culture_speciale, surface_terrain, longitude, latitude`. **Une mutation = plusieurs lignes** (un local ou une parcelle par ligne, la `valeur_fonciere` est répétée sur chaque ligne) : il faut regrouper par `id_mutation`.

### Prototype sur Chaponost (69043), maisons — `scratchpad/next/dvf/proto.py`
- Ventes « une seule maison » 2021–2025 : **283** ; médiane €/m² par an : 2021 **4 956** · 2022 **5 252** · 2023 **4 757** · 2024 **4 254** · 2025 **4 279**.
- Comparables (30 derniers mois, surface 115 m² ± 30 %) : **91** ; Q1 / médiane / Q3 = **3 924 / 4 418 / 5 011 €/m²** (en cohérence avec la maquette : 3 800 / 4 350 / 5 200).
- Évolution sur 1 an (médiane 2025 vs 2024) : **+0,6 %**. Mais une droite sur 5 ans donne −4,8 %/an et une droite sur 30 mois −6,1 %/an : **une tendance linéaire communale est instable** (pic 2022, petits effectifs). → Conception : indice annuel par médianes, lissé vers l’EPCI/département et plafonné (§3.4).
- Exemple réel : maison 115 m², 5 p., 587 m² de terrain, vendue 405 701 € en avril 2025 à 350 m du point test. Les écarts entre ventes semblables (3 500 → 4 500 €/m²) justifient une fourchette large et un score de confiance.

**Conclusions sur les sources** : v1 = **geo-dvf par commune** (ventes individuelles) + **Statistiques DVF (API tabulaire)** pour la tendance lissée en repli. Fraîcheur réelle : la vente la plus récente a ~9 mois, la prochaine republication Etalab (avec 1er semestre 2026) est attendue vers nov. 2026 → la date de dernière vente doit être affichée. Mentions obligatoires : « Source : DGFiP, Demandes de valeurs foncières (DVF), traitement Etalab — Licence Ouverte 2.0 ». CGU DGFiP : pas de ré-identification des personnes, pas d’indexation par les moteurs de recherche. Décision du porteur de projet : afficher le **nom de la rue sans numéro** (`adresse_nom_voie`) ; jamais le numéro, la parcelle ni l’`id_mutation` ; les écrans sont derrière l’authentification (non indexables). Vigilance : dans une rue de 2–3 maisons, rue + surface + mois peuvent suffire à reconnaître un vendeur (voir Q2).

---

## 2. Architecture

```
App (V7 « Envoyer » réussi ; V8 « Réessayer » seulement si aucun résultat n’existe)
  └─ supabase.functions.invoke('estimate-property', body: {property_id})   (JWT utilisateur)
       Edge Function Deno `estimate-property`
        1. client « utilisateur » (Authorization du JWT) : lit properties + property_parcels + rooms
           + lifestyle_items → RLS garantit que c’est SON dossier (sinon 404)
        2. refuse si status ≠ 'submitted' / 'in_review' (409) ou si données insuffisantes (422 + raison)
        3. CALCUL UNIQUE : si un market_snapshot 'ok' ou 'insufficient' existe déjà pour ce bien,
           le renvoie tel quel (jamais de recalcul, même si le dossier a changé depuis) ;
           un snapshot 'error' n’empêche pas une nouvelle tentative
        4. client « service » : charge/rafraîchit le cache DVF des communes nécessaires
           (dvf_sales, dvf_sources) depuis files.data.gouv.fr ; tendance via tabular-api
        5. calcul déterministe (TypeScript pur, testé) → chiffres
        6. OpenRouter (Claude) : rédige l’explication FR à partir d’un JSON de chiffres
           (validation : aucun nombre inventé, sinon texte de repli par gabarit)
        7. client « service » : snapshot 'running' créé à l’étape 3, passé à 'ok' / 'insufficient' / 'error'
           + update properties.ai_estimate_* (une seule fois)
        8. renvoie le snapshot
```

- Les colonnes `ai_estimate_*` n’ont **pas de droit `update`** pour `authenticated` (migration `create_seller_tunnel`) : seul le rôle service les écrit, **après** vérification de propriété par la lecture RLS avec le JWT. Le rôle service n’est jamais exposé ; il est disponible dans la fonction (`SUPABASE_SERVICE_ROLE_KEY`).
- Pourquoi pas une écriture sous le JWT : l’utilisateur pourrait alors écrire n’importe quelle estimation. Pourquoi pas un trigger SQL + `pg_net` : le calcul + HTTP + IA est plus simple et testable en Deno.
- Limites Edge Functions (à revérifier dans la doc Supabase) : ~2 s de **CPU** par requête (les attentes réseau ne comptent pas), 256 Mo, ~150 s de durée sur le plan gratuit. Un CSV commune fait 50–100 Ko : parsing négligeable ; 5 ans × ~10 communes voisines ≈ 50 fichiers au premier calcul d’un secteur → téléchargements en parallèle (limite 6 simultanés), puis cache en base.

### 2.1 Déclenchement depuis l’app (calcul unique à l’envoi)
1. **À l’envoi V7** (`DocumentsCubit` submit → succès) : appel *fire-and-forget* (`unawaited`) ; V8 s’affiche sans attendre. V8 montre « Calcul de votre tendance de prix… » (squelette de la carte) tant qu’aucun résultat n’existe, puis recharge le bien et le snapshot.
2. **Filet de sécurité** : si l’app a été fermée avant la fin, ou si le calcul a échoué (réseau, DVF indisponible), V8 relance le **même** appel à l’ouverture (une fois) puis propose « Réessayer ». Le serveur étant idempotent (étape 3), ces appels ne recalculent jamais un résultat existant.
3. **Jamais de recalcul** ensuite : ni modification du dossier, ni republication DVF, ni bouton « Actualiser ». Seul un administrateur (rôle service) peut supprimer un snapshot pour forcer un nouveau calcul (ex. correctif de méthode).
- Pas d’estimation pour un brouillon : la fonction exige `status in ('submitted','in_review')`.
- La carte reste **masquée une fois certifié** (comportement actuel US-04.9).
- Variante (Q1) : déclencher côté serveur par un trigger `status → submitted` + `pg_net` (indépendant de l’app) ; v1 proposée : appel depuis l’app + filet de sécurité, plus simple.

---

## 3. Algorithme (déterministe, module `supabase/functions/_shared/estimation/`)

### 3.1 Entrées lues (JWT utilisateur)
`properties` : `property_type`, `lat`, `lng`, `address_citycode` (INSEE), `address_city`, `living_area_m2`, `annex_area_m2`, `rooms_count`, `bedrooms_count`, `construction_year`, `outdoor_equipment`, `pool_type`, `heating_systems`, `heat_pump_year`, `roof_year`, `levels`, `adjacency`, `noise_level`, `overlooking`, `provenance` ; `property_parcels.area_m2` (somme = terrain) ; `rooms` (salle de bain…, uniquement pour les facteurs) ; `lifestyle_items` (atouts / vigilance, pour les facteurs).
Pré-requis : type `maison` ou `appartement`, `lat/lng`, INSEE, `living_area_m2` ∈ [9 ; 1 000]. Sinon 422 `reason` (`unsupported_type` pour terrain/autre, `missing_area`, `missing_location`, `no_dvf_coverage` pour 57/67/68/976).

### 3.2 Nettoyage DVF (par mutation) — « valeurs aberrantes écartées »
- `nature_mutation` ∈ {Vente, Vente en l’état futur d’achèvement, Adjudication} ; regroupement des lignes par `id_mutation`.
- **Ventes multi-lots écartées** : exactement **un** local principal (Maison ou Appartement) dans la mutation, du même type que le bien ; pas de local commercial mêlé ; plusieurs parcelles autorisées pour une maison (terrain = somme des `surface_terrain` des parcelles distinctes).
- **Dépendances seules écartées** : mutation sans Maison ni Appartement (garage, cave, parking) ; une dépendance **accompagnant** le logement est tolérée (cas normal du garage).
- `surface_reelle_bati` ≥ 9 m² ; pièces = `nombre_pieces_principales` ; rue = `adresse_nom_voie` (mise en forme « Rue Jean Eugene Culet » ; DVF n’a pas d’accents).
- **€/m² extrêmes écartés** : hors 500–25 000 €/m², puis hors [Q1 − 1,5·IQR ; Q3 + 1,5·IQR] des ventes du même type de la commune (sur 5 ans, après projection à aujourd’hui).
- Stockage : seules les ventes retenues vont dans `dvf_sales` (+ compteurs d’écartées par motif dans `dvf_sources`).

### 3.3 Sélection des comparables (élargissement progressif)
Filtres communs : même type ; surface habitable **± 30 %** ; ventes des **36 derniers mois** de données.
| Palier | Zone | Arrêt si |
|---|---|---|
| 1 | ≤ **500 m** du bien | ≥ 10 comparables |
| 2 | ≤ **1 km** | ≥ 10 |
| 3 | ≤ **2 km** | ≥ 10 |
| 4 | **commune entière** (INSEE du bien ; arrondissement à Paris / Lyon / Marseille) | — |
Au palier 4, si < 10 comparables sur 36 mois, la période passe à **60 mois** (5 ans, tout l’historique geo-dvf). **Si le total final est < 5 → aucune estimation** (`status = 'insufficient'`, message « l’expert s’en charge », §5).
Les ventes situées hors de la commune mais à ≤ 2 km (paliers 1–3, communes voisines repérées par `communes_ref`) sont incluses ; au palier 4 on se limite à la commune.
Poids de chaque comparable : `w = w_dist × w_temps` avec **proximité** `w_dist = 1 / (1 + d / 500 m)` et **ancienneté** `w_temps = 0,5^(âge en mois / 24)`.

### 3.4 Courbe semestrielle et projection à aujourd’hui
- **Courbe** : médiane du €/m² par **semestre** (S1 = janv.–juin, S2 = juil.–déc.) sur les **5 dernières années** (10 points), pour le type du bien, à l’échelle de la **commune** si chaque semestre compte ≥ 8 ventes, sinon de l’**EPCI** (Statistiques DVF mensuelles de l’API tabulaire, agrégées en semestres pondérés par les volumes), sinon du **département**. Lissage : médiane glissante sur 3 semestres. La courbe est stockée (`semester_medians`) pour un futur graphique sur V8b (Q6).
- **Projection d’une vente passée à aujourd’hui** : `pm2_projeté = pm2 × indice(dernier semestre) / indice(semestre de la vente)` × extrapolation du dernier semestre connu jusqu’à la date du calcul, au rythme de l’évolution des 12 derniers mois **plafonnée à ±5 %/an** (les données s’arrêtent ~9 mois avant aujourd’hui).
- **Évolution des prix sur 1 an** (tuile V8b) = médiane des 12 derniers mois connus / médiane des 12 mois précédents − 1 (même échelle que la courbe).
- Leçon du prototype (Chaponost) : une droite sur 5 ans donnait −4,8 %/an alors que 2025/2024 = +0,6 % → l’indice par semestre (et non une droite) est indispensable.

### 3.5 Valeur de base, fourchette et ajustements visibles
- **Base** : `pm2_med` = **médiane pondérée** des €/m² projetés ; `pm2_q1`, `pm2_q3` = **quartiles pondérés** ; `base_eur = pm2_med × living_area_m2`.
- **Ajustements simples et visibles** (chacun affiché avec son effet sur V8b ; paramètres versionnés dans `method_version`, à valider — Q3) :
  | Ajustement | Règle proposée | Exemple d’affichage |
  |---|---|---|
  | Part des annexes | `annex_area_m2 × 30 % × pm2_med` (garage, cellier, sous-sol comptés à 30 % d’un m² habitable) | « + Annexes 20 m² comptées à 30 % : +27 000 € » |
  | Grand terrain (maison) | si terrain > 1,5 × médiane des terrains des comparables : +2 % par doublement au-delà, plafonné à +6 % ; si < 0,5 × : −2 % par moitié, plafonné à −4 % | « + Terrain de 1 200 m² (médiane secteur 600 m²) : +2 % » |
  | Année de construction | ≤ 10 ans : +5 % ; 1949–1974 : −3 % ; sinon 0 | « + Construction récente (2019) : +5 % » |
  | Piscine (maison) | +3 % si `piscine` dans `outdoor_equipment` | « + Piscine enterrée : +3 % » |
  | Garage | +2 % (maison) / +3 % (appartement, place ou box) si `garage` | « + Garage : +2 % » |
  Total des pourcentages plafonné à **±12 %** ; l’ajustement annexes s’ajoute en euros. DVF ne connaît ni piscine ni garage des comparables : l’ajustement suppose un comparable « moyen », ce qui est dit dans l’explication.
- `median_eur = round(base_eur × (1 + Σ%) + annexes_eur, -3)`.
- **Fourchette** : `low/high = median_eur × exp(∓ z)` avec `z = 0,5 × ln(pm2_q3 / pm2_q1)` élargi quand la confiance baisse (`× (1 + (60 − confiance) / 100)`), borné entre **±5 %** et **±20 %** ; arrondis au millier.
- **Facteurs non chiffrés** (listés sans effet, signe + / −) : PAC récente, toiture refaite, bruit ≥ 7, vis-à-vis important, atouts / points de vigilance V6, salle de bain à rafraîchir… (règles déterministes sur les réponses).

### 3.6 Indice de confiance (0–100)
`confiance = 100 × (0,35·f_n + 0,25·f_disp + 0,15·f_dist + 0,15·f_récence + 0,10·f_données)` :
`f_n = min(1, n_eff / 20)` (n_eff = (Σw)² / Σw²) ; `f_disp = clamp(1 − (IQR/médiane − 0,15) / 0,35)` ; `f_dist` = 1 (500 m), 0,8 (1 km), 0,6 (2 km), 0,4 (commune), 0,3 (commune sur 5 ans) ; `f_récence = clamp(1 − (âge médian des ventes − 6) / 30 mois)` ; `f_données` = part des entrées clés présentes (surface, pièces, terrain, année de construction).
Niveaux affichés : ≥ 70 « élevée », 40–69 « moyenne », < 40 « faible ». La règle de publication est le **seuil de 5 comparables** (décision du porteur de projet), pas la confiance.

### 3.7 Sortie (JSON de la fonction = colonnes de `market_snapshots`)
```json
{
  "status": "ok",
  "computed_at": "2026-10-01T15:10:00Z",
  "estimate": {"low_eur": 445000, "median_eur": 498000, "high_eur": 556000, "price_m2_eur": 4330},
  "base": {"price_m2_median": 4206, "base_eur": 484000},
  "adjustments": [
    {"kind": "pool", "pct": 3.0, "eur": 14500, "label": "Piscine enterrée"},
    {"kind": "annexes", "pct": null, "eur": 0, "label": null}
  ],
  "confidence": {"score": 72, "level": "elevee"},
  "sector": {"price_m2_low": 3924, "price_m2_median": 4418, "price_m2_high": 5011,
             "scope": "radius", "radius_m": 1000, "months": 36, "label": "Chaponost", "comparables_count": 23},
  "sales_12m": 60, "yoy_change_pct": 0.6,
  "semester_medians": [{"semester": "2021-S1", "median_m2": 4890, "count": 31, "scale": "commune"}, "…"],
  "comparables": [{"type": "maison", "street": "Rue Jean Eugene Culet", "area_m2": 115, "rooms": 5,
                   "land_m2": 587, "sold_on": "2025-04", "distance_m": 350,
                   "price_eur": 405701, "price_m2_eur": 3528, "price_m2_today_eur": 3540, "weight": 0.61}],
  "factors": [{"sign": "+", "label": "Pompe à chaleur 2021 et toiture refaite en 2016"}],
  "explanation_fr": "…",
  "data_until": "2025-12-29", "source_version": "geo-dvf 2026-05-18 / stats 2026-07-17",
  "method_version": "dvf-v1"
}
```
(`status: "insufficient"` → `comparables_count < 5`, aucune valeur d’estimation, pas d’appel IA.)

### 3.8 Rôle de l’IA (OpenRouter, Claude) — rédaction seulement
- Appel unique `POST https://openrouter.ai/api/v1/chat/completions`, `Authorization: Bearer ${OPENROUTER_API_KEY}` (secret déjà présent), en-têtes `HTTP-Referer`/`X-Title: Realesty`. Modèle configurable par secret `OPENROUTER_MODEL_ESTIMATE` ; défaut proposé `anthropic/claude-opus-5.5` (≈ 1,5 k jetons entrée + 300 sortie ≈ 0,012 $ par calcul aux tarifs OpenRouter relevés : 4 $/20 $ par M ; `anthropic/claude-sonnet-5.5` à 2 $/10 $ ou `anthropic/claude-haiku-4.5` à 1 $/5 $ si le porteur de projet préfère réduire le coût, décision Q9). `response_format: {type: "json_schema", strict}` → `{ "explanation": string (≤ 600 car.), "factor_labels": [{ "sign", "label" }] }` ; pas de `tool_choice` forcé (refusé par les derniers modèles Claude).
- Prompt système : « Tu es l’agent Realesty. Rédige en français, vouvoiement, 3 phrases max, ton prudent. Utilise UNIQUEMENT les nombres du JSON fourni, recopiés à l’identique ; n’ajoute aucun chiffre, aucune promesse ; rappelle que c’est indicatif et non validé par un professionnel. » Les champs libres de l’utilisateur (atouts, note) sont passés comme données dans un bloc délimité, jamais comme instructions.
- **Garde-fou** : extraction de tous les nombres du texte (`/\d[\d\s  ,.]*/`) → chacun doit correspondre à un nombre du JSON d’entrée (après normalisation française) ; sinon, ou si timeout 10 s / erreur → texte de repli par gabarit : « D’après {n} ventes de {type}s comparables autour de {commune} depuis {mois année}, le prix médian ressort à {pm2} €/m², soit une tendance de {low} à {high} € pour {surface} m². Chiffres indicatifs, non validés par un professionnel. » L’échec de l’IA **ne bloque jamais** l’estimation.


### 3.9 Calcul unique et cache des données
- `market_snapshots` : **un seul résultat définitif par bien** (index unique partiel `where status in ('ok','insufficient')`). Une tentative en échec (`error`) est conservée pour le diagnostic et n’empêche pas de réessayer. Aucune notion d’expiration.
- `dvf_sources (insee, year)` : `etag`, `last_modified`, `fetched_at`, compteurs. Revalidation par `HEAD` (ETag) au plus une fois par 7 jours — utile aux **autres** biens du secteur, jamais à un bien déjà estimé.
- `dvf_sales` : ventes nettoyées, interrogées en SQL (filtre bbox + distance haversine) : pas de re-téléchargement par estimation.
- Concurrence (double appel envoi + filet de sécurité) : ligne `market_snapshots` `status = 'running'` insérée d’abord ; un second appel pendant un calcul `running` de moins de 120 s reçoit 202 et V8 re-interroge.

---

## 4. Données / migrations (nouvelle migration `*_market_estimation.sql`, purement additive)

```sql
-- Référentiel communes (centre) pour les communes voisines ; rempli par une fonction d'import.
create table public.communes_ref (
  insee text primary key check (char_length(insee) = 5),
  name text not null, departement text not null, epci text,
  lat double precision not null, lng double precision not null,
  population integer, updated_at timestamptz not null default now()
);
-- Cache DVF (service uniquement : RLS activée, aucune policy, aucun grant à anon/authenticated).
create table public.dvf_sources (
  insee text not null, year smallint not null,
  etag text, last_modified timestamptz, fetched_at timestamptz not null,
  rows_kept integer not null default 0,
  rows_dropped jsonb not null default '{}',   -- compteurs par motif (multi_lots, dependances, extreme…)
  primary key (insee, year)
);
create table public.dvf_sales (
  id_mutation text not null, insee text not null, sold_on date not null,
  property_type text not null check (property_type in ('maison','appartement')),
  price_eur integer not null, built_area_m2 numeric(7,2) not null,
  rooms smallint, land_m2 integer,
  street text check (char_length(street) <= 200),   -- adresse_nom_voie, jamais le numéro
  lat double precision, lng double precision,
  primary key (id_mutation, insee)
);
create index dvf_sales_lookup on public.dvf_sales (insee, property_type, sold_on);
-- Résultat par bien (spec §4, complété) : calcul unique à l'envoi.
create table public.market_snapshots (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  status text not null check (status in ('running','ok','insufficient','error')),
  computed_at timestamptz not null default now(),
  method_version text not null, source_version text, data_until date,
  estimate_low_eur integer, estimate_median_eur integer, estimate_high_eur integer,
  base_price_m2 integer, adjustments jsonb,           -- [{kind, pct, eur, label}]
  price_m2_low integer, price_m2_median integer, price_m2_high integer,
  confidence smallint check (confidence between 0 and 100),
  comparables_count smallint, scope text, radius_m integer, months smallint,
  sales_12m integer, yoy_change_pct numeric(5,2),
  semester_medians jsonb, comparables jsonb, factors jsonb,
  avg_days_on_market integer,           -- null en v1 (annonces)
  listings_summary jsonb,               -- null en v1
  explanation_fr text check (char_length(explanation_fr) <= 1000),
  explanation_source text check (explanation_source in ('ai','template')),
  error text,
  created_at timestamptz not null default now()
);
create unique index market_snapshots_one_result
  on public.market_snapshots (property_id) where status in ('ok','insufficient');
create index market_snapshots_property_idx on public.market_snapshots (property_id, computed_at desc);
alter table public.market_snapshots enable row level security;
create policy "Owners can view the market snapshots of their properties"
  on public.market_snapshots for select to authenticated
  using (exists (select 1 from public.properties p
                 where p.id = property_id and p.owner_id = (select auth.uid())));
revoke all on public.market_snapshots from anon, authenticated;
grant select on public.market_snapshots to authenticated;   -- lecture seule
-- + properties.ai_estimate_confidence smallint (0–100), écrit par le service uniquement (pas de grant update).
```
- `properties.ai_estimate_low/median/high_eur` et `ai_estimate_computed_at` existent déjà (écrits une fois, par le service) ; on ajoute `ai_estimate_confidence`. La provenance de l’estimation est implicite (« Estimé IA » sur la carte), pas d’entrée dans `provenance` (qui décrit les réponses).
- `dvf_*` et `communes_ref` : RLS activée sans policy ni grant (inaccessibles depuis l’app). Les comparables affichés (rue sans numéro, surface, pièces, mois, distance, prix) sont recopiés dans `market_snapshots.comparables`, lisible par le seul propriétaire.
- Purge : `on delete cascade` avec le bien ; `dvf_sales` est un cache reconstructible.

---

## 5. Écrans — correspondance maquettes ↔ données

### V8 · carte « Tendance IA » (`AttenteExpert.dc.html`, widget existant `AiEstimateCard`)
| Élément maquette | Donnée | Règle |
|---|---|---|
| `TENDANCE IA` + badge `Indicative` | statique | existant |
| `495 000 – 540 000 €` | `ai_estimate_low_eur` – `ai_estimate_high_eur` | existant (`frenchNumber`) |
| barre + `495 k€` · **`Médiane 518 k€`** · `540 k€` | low / median / high | existant |
| `Calculée le 24/09/2026 à partir de vos réponses, documents et références de marché. Non validée par un professionnel.` | `ai_estimate_computed_at` | existant ; nouveau : `Fiabilité : élevée / moyenne / faible` (12/700) — à valider design (Q5) |
| bouton secondaire `Voir la synthèse du marché` (icône graphique + chevron) | → `/vendeur/marche` (V8b) | démasqué quand le snapshot est `ok` |
| (non dessiné) calcul en cours | snapshot absent ou `running` | squelette de la carte + `Calcul de votre tendance de prix…` |
| (non dessiné) moins de 5 ventes | snapshot `insufficient` | carte sobre : titre `Tendance IA`, texte `Trop peu de ventes comparables près de chez vous pour une tendance fiable : l’expert s’en charge dans votre avis de valeur.` ; pas de bouton V8b |
| (non dessiné) échec | snapshot `error` ou appel en échec | `Votre tendance n’a pas pu être calculée.` + bouton texte `Réessayer` (même appel idempotent) |
Pas de bouton « Actualiser » : le résultat est définitif (décision 1).

### V8b · Synthèse du marché (`SyntheseMarche.dc.html`) — nouvelle page lue depuis le snapshot `ok`
| # | Maquette | Source v1 | Note |
|---|---|---|---|
| en-tête | retour · `Synthèse du marché` · `Partager` | — | **Partager masqué v1** (Q7) |
| 1 | badge `Indicatif` ; badge horloge `Mis à jour le 24/09/2026` | `computed_at` | libellé v1 : `Calculée le {date}` (le résultat n’est jamais mis à jour) |
| 2 | `Votre bien face au marché` ; `Maison 115 m² · Chaponost · tendance IA 518 000 €, soit environ 4 504 €/m².` | `property_type`, `living_area_m2`, `address_city`, `estimate_median_eur`, médiane / surface | gabarit l10n |
| 3 | carte `Prix au m² dans votre secteur` : bande `3 800 €/m²` · `Médiane secteur 4 350 €/m²` · `5 200 €/m²` + marqueur maison | `price_m2_low/median/high` (quartiles / médiane pondérés des comparables projetés) ; marqueur = `estimate_median_eur / living_area_m2` | nouveau widget `MarketRangeBar` ; sous la carte, 12 discret : `{n} ventes comparables · rayon {500 m / 1 km / 2 km / commune} · {3 / 5} ans` |
| 4 | tuiles : `58 j Délai de vente moyen` · `34 Ventes sur 12 mois` · `+2,1 % Évolution des prix sur 1 an` | délai : **masqué** (annonces) ; `sales_12m` ; `yoy_change_pct` | 2 tuiles en v1 (Q8) |
| 4 bis | (nouveau, optionnel) courbe `Prix au m² médian par semestre` (5 ans, ventes projetées) | `semester_medians` | à dessiner (Q6) ; sinon non affichée |
| 5 | `Ventes comparables récentes` : `Maison 108 m² · 5 p.` / `Vendue en mars 2026 · à 400 m` / `498 000 €` / `4 611 €/m²` | `comparables[0..2]` triés par poids | **sous-titre v1 : `{Rue} · vendue en {mois année} · à {distance}`** (rue sans numéro, décision 2), ex. `Rue Jean Eugene Culet · vendue en avril 2025 · à 350 m` ; distance arrondie (50 m sous 1 km, sinon 0,1 km) ; bouton texte `Voir les {n} ventes` → liste complète (même format) |
| 6 | `Ce qui influence votre estimation` (+ / −) | `adjustments` **avec leur effet** (`+ Piscine enterrée · +3 %`, `+ Annexes 20 m² comptées à 30 % · +27 000 €`) puis `factors` non chiffrés | |
| 6 bis | (nouveau, sous 6) paragraphe explicatif | `explanation_fr` | à valider design |
| 7 | `Biens similaires en vente` · `5 annonces` · … | annonces | **masqué v1** |
| 8 | `Sources : ventes notariées (DVF) et annonces actives du secteur. Chiffres indicatifs, analysés et sera ajustés…` | — | v1 : `Sources : ventes notariées (DVF, DGFiP – traitement Etalab, Licence Ouverte 2.0), connues jusqu’en {mois année}. Chiffres indicatifs, analysés et ajustés par notre expert dans votre avis de valeur.` |
| 9 | `Consulter le rapport complet` (→ V9b) · `Retour au suivi de mon dossier` (→ V8) | — | 1er masqué v1 (V9b non construit) |
| — | flottant `Une question ?` | EPIC-06 | masqué |

---

## 6. User stories (FR) et critères d’acceptation

### US-05.1 · Données DVF disponibles côté serveur
*En tant que porteur de projet, je veux que les ventes DVF du secteur d’un bien soient chargées et nettoyées automatiquement, pour calculer des estimations sans dépendre d’une API instable.*
- [ ] Les ventes geo-dvf (5 derniers millésimes) des communes nécessaires sont téléchargées depuis `files.data.gouv.fr`, regroupées par mutation et stockées dans `dvf_sales` avec le nom de rue (sans numéro).
- [ ] Sont écartées : ventes multi-lots, ventes de dépendances seules, €/m² extrêmes (bornes fixes puis règle des quartiles) ; les compteurs d’écartées sont conservés.
- [ ] Un fichier déjà chargé n’est re-téléchargé que si son `ETag` a changé (vérification ≤ 1 fois / 7 jours).
- [ ] Une commune sans fichier (Alsace-Moselle, Mayotte, aucune vente) est enregistrée comme vide, sans erreur.
- [ ] Les tables `dvf_*` et `communes_ref` ne sont lisibles ni par `anon` ni par `authenticated`.

### US-05.2 · Calcul unique de la tendance de prix
*En tant que vendeur, je veux une première fourchette de prix indicative, calculée à l’envoi de mon dossier à partir de ventes réelles proches.*
- [ ] `estimate-property` n’accepte que le propriétaire du bien (JWT ; sinon 404) et un dossier envoyé ou en examen (sinon 409).
- [ ] Maison et appartement uniquement ; terrain / autre, surface ou localisation manquante → 422 avec une raison, sans estimation.
- [ ] Comparables du même type, surface habitable ± 30 %, rayon élargi 500 m → 1 km → 2 km → commune, sur 3 ans (5 ans au niveau commune si nécessaire).
- [ ] **Moins de 5 comparables → aucune estimation** (`insufficient`), sans appel IA.
- [ ] Médiane et quartiles pondérés (proximité, ancienneté) du €/m² des ventes projetées à aujourd’hui avec la courbe semestrielle (projection au-delà des données plafonnée à ±5 %/an).
- [ ] Ajustements visibles : annexes à 30 %, grand terrain, année de construction, piscine, garage ; total des pourcentages plafonné à ±12 %.
- [ ] Fourchette arrondie au millier, médiane comprise entre les bornes, largeur entre ±5 % et ±20 % ; indice de confiance 0–100.
- [ ] **Calcul unique** : un second appel renvoie le résultat existant, même si le dossier a été modifié ; seul un échec permet une nouvelle tentative.
- [ ] Tests unitaires Deno du module de calcul sur un jeu de ventes figé (dont l’extrait réel de Chaponost).

### US-05.3 · Explication rédigée par l’agent
*En tant que vendeur, je veux comprendre en quelques phrases d’où vient cette tendance.*
- [ ] Texte de 3 phrases max, en français, vouvoiement, mentionnant le caractère indicatif et la non-validation par un professionnel.
- [ ] Tout nombre du texte figure dans les chiffres calculés ; sinon le texte gabarit est utilisé.
- [ ] Une panne ou un délai (> 10 s) d’OpenRouter n’empêche pas l’estimation (texte gabarit, `explanation_source = 'template'`).
- [ ] Aucune donnée personnelle (nom, téléphone, e-mail, adresse du bien) n’est envoyée à OpenRouter : seulement type, commune, surfaces, équipements, facteurs et chiffres.

### US-05.4 · Tendance IA sur V8
*En tant que vendeur qui vient d’envoyer son dossier, je veux voir ma tendance de prix dès qu’elle est prête.*
- [ ] L’envoi V7 déclenche le calcul sans retarder l’affichage de V8 ; si l’app a été fermée avant la fin, V8 relance l’appel une fois à l’ouverture.
- [ ] V8 affiche « calcul en cours », puis la carte Tendance IA (fourchette, médiane, date, fiabilité) sans relancer l’app.
- [ ] Moins de 5 ventes : « Trop peu de ventes comparables… l’expert s’en charge » ; échec : « Réessayer ».
- [ ] Aucun bouton d’actualisation ; la carte reste masquée pour un dossier certifié.
- [ ] « Voir la synthèse du marché » apparaît quand l’estimation existe.

### US-05.5 · Synthèse du marché (V8b)
*En tant que vendeur, je veux voir comment mon bien se situe par rapport aux ventes de mon secteur.*
- [ ] Phrase de synthèse, bande des prix au m² (Q1 / médiane / Q3) avec la position de mon bien, nombre de ventes, rayon et période utilisés.
- [ ] Tuiles « Ventes sur 12 mois » et « Évolution des prix sur 1 an » ; ni délai de vente ni annonces en v1.
- [ ] 3 ventes comparables (type, surface, pièces, **rue sans numéro**, mois, distance arrondie, prix, €/m²) et accès à la liste complète.
- [ ] Ajustements avec leur effet chiffré, facteurs + / − non chiffrés, explication de l’agent.
- [ ] Mention des sources DVF / Etalab / Licence Ouverte et du mois des dernières ventes connues.
- [ ] Lecture seule ; retour vers V8 ; textes en fr / en / es ; 100 % de couverture.

---

## 7. Découpage (tranches de 1 à 2 h, un agent codeur chacune)

| # | Tranche | Fichiers possédés (exclusifs) | Dépend de |
|---|---|---|---|
| E1 | **Migration** `market_estimation` (tables §4, RLS, grants, index unique, colonne `ai_estimate_confidence`) + `supabase db push` + sonde RLS anon / authenticated | `supabase/migrations/2026…_market_estimation.sql` | — |
| E2 | **Module DVF** Deno : téléchargement commune × année (ETag), parsing CSV, regroupement par mutation, filtres §3.2 (multi-lots, dépendances, extrêmes), rue sans numéro ; tests sur fixtures (CSV Chaponost réduit) | `supabase/functions/_shared/dvf/**` | — (E1 pour l’écriture réelle) |
| E3 | **Calcul 1/2** : paliers 500 m / 1 km / 2 km / commune, période 3 → 5 ans, poids, médiane et quartiles pondérés, seuil des 5 comparables, confiance ; tests | `supabase/functions/_shared/estimation/comparables.ts`, `stats.ts`, `confidence.ts` (+ tests) | — (types figés en début de tranche) |
| E4 | **Calcul 2/2** : courbe semestrielle (commune / EPCI via API tabulaire / département), lissage, projection à aujourd’hui, évolution 1 an, ajustements visibles (annexes, terrain, année, piscine, garage, plafond), fourchette, facteurs non chiffrés ; tests | `supabase/functions/_shared/estimation/trend.ts`, `adjustments.ts`, `range.ts`, `factors.ts` (+ tests) | E3 (types) |
| E5 | **Import `communes_ref`** (centres + EPCI depuis geo.api.gouv.fr, arrondissements inclus) | `supabase/functions/seed-communes/**` ou `supabase/seed/communes.sql` | E1 |
| E6 | **Rédaction IA** : client OpenRouter partagé (avec EPIC-06 A3, un seul propriétaire), prompt, vérificateur de nombres, gabarit de repli ; tests avec réponse simulée | `supabase/functions/_shared/openrouter/**`, `supabase/functions/_shared/estimation/explain.ts` | E3 (types) |
| E7 | **Edge Function `estimate-property`** : auth JWT, lecture RLS, contrôles, **calcul unique** (snapshot `running` / index unique), orchestration, écritures service ; déploiement ; test de bout en bout sur un dossier de test | `supabase/functions/estimate-property/**`, `supabase/config.toml` (`[functions.estimate-property]`) | E1, E2, E3, E4, E5, E6 |
| E8 | **`property_repository`** : modèle `MarketSnapshot` (comparables, ajustements, facteurs, courbe), `estimateProperty(id)` (`functions.invoke`), `getMarketSnapshot(id)` ; champ `aiEstimateConfidence` ; tests | `packages/property_repository/lib/src/models/market_snapshot.dart`, `…/property_repository.dart`, `…/models/property.dart` (1 champ), tests | E1 |
| E9 | **V8** : déclenchement après envoi V7, filet de sécurité à l’ouverture, `AiEstimateCubit` (computing / ready / insufficient / failed), états de la carte, fiabilité, lien V8b ; l10n `submittedAi*` ; tests | `lib/seller_tunnel/steps/submitted/**`, `lib/seller_tunnel/steps/documents/cubit/documents_cubit.dart` (un appel), ARB | E8 |
| E10 | **V8b** `MarketSynthesisPage` (route `/vendeur/marche`, accessible dossier verrouillé), `MarketRangeBar`, tuiles, comparables (rue), liste complète, ajustements et facteurs, explication, sources ; l10n `market*` ; tests 100 % | `lib/seller_tunnel/market/**`, routeur (ajout de route), ARB | E8 (+E9 pour le lien) |
| E11 | **Docs & vérification** : `docs/epics/EPIC-05-estimation.md`, plan `docs/plans/2026-10-0x-estimation.md`, spec §3 / §4, cspell (DVF, Etalab, geo-dvf), rendu 390×844 vs maquettes, test iPhone | `docs/**`, `.github/cspell.json` | toutes |

Parallélisme : vague 1 = E1, E2, E3, E6 ; vague 2 = E4, E5, E8 ; vague 3 = E7, E9 ; vague 4 = E10 ; puis E11. ARB : lecture-modification-écriture JSON suivie immédiatement de `flutter gen-l10n` ; E9 et E10 ont des préfixes de clés distincts.

CI : ajouter un job `deno test` / `deno lint` / `deno fmt --check` pour `supabase/functions` (le contrôle de licences Dart n’est pas concerné). Dépendances Deno : `jsr:@supabase/supabase-js@2` (MIT) et éventuellement `jsr:@std/csv` (MIT).

---

## 8. Questions ouvertes (porteur de projet)
1. **Déclenchement** : appel depuis l’app à l’envoi + filet de sécurité à l’ouverture de V8 (proposé), ou trigger serveur `status → submitted` (`pg_net`) indépendant de l’app ?
2. **Rue des comparables** : dans une rue de 2–3 maisons, rue + surface + mois peuvent identifier le vendeur (CGU DGFiP : pas de ré-identification). Masquer la rue quand elle compte moins de N ventes sur 5 ans (ex. N = 3) ?
3. **Paramètres des ajustements** (annexes 30 %, terrain ±2 % par doublement / moitié plafonné +6 % / −4 %, construction ≤ 10 ans +5 %, 1949–1974 −3 %, piscine +3 %, garage +2 % / +3 %, total ±12 %) : à valider ou à fournir.
4. **Fraîcheur** : DVF s’arrête à fin 2025 (prochaine publication ~nov. 2026) ; affichage « ventes connues jusqu’en déc. 2025 » sur V8b — d’accord ?
5. **Fiabilité** (élevée / moyenne / faible) sur la carte V8 : à ajouter au design ?
6. **Courbe semestrielle** sur V8b : l’afficher (à dessiner) ou la garder pour l’expert et V9b ?
7. **Partager** (V8b) : masqué en v1 (proposé) ?
8. Tuile « Délai de vente moyen » : la masquer ou la remplacer par « Ventes analysées {n} » ?
9. **Modèle IA** de l’explication : défaut `anthropic/claude-opus-5.5` (≈ 0,012 $ par estimation, calculée une seule fois) ; Sonnet 5.5 / Haiku 4.5 possibles. RGPD : routage Anthropic seulement, `data_collection: "deny"`.
10. Appartements : surface Carrez (`lot*_surface_carrez`) plutôt que `surface_reelle_bati` quand elle existe ? Paris / Lyon / Marseille : par arrondissement (proposé) ?

## Arbitrages du porteur de projet (2026-10-01)
- **Pas d'ajustements en v1** : estimation = prix au m² du secteur × surface habitable, avec fourchette (quartiles). Les ajustements (annexes, terrain, année, piscine, garage) sont retirés du périmètre v1 ; la section « Ce qui influence votre estimation » ne montre que des facteurs non chiffrés.
- **Discrétion** : la rue d'une vente comparable n'est affichée que si au moins 3 ventes y figurent ; sinon « Secteur proche · 400 m ».
- Rappels : calcul unique à l'envoi, pas d'estimation sous 5 ventes comparables, l'IA rédige seulement l'explication.

## Journal d'exécution

- **2026-10-01 · E1 migration** `20261001162617_market_estimation.sql` poussée : `dvf_sources`, `dvf_sales` (service uniquement), `market_snapshots` (lecture propriétaire, index uniques `ok/insufficient` et `running`, colonne `reason`), `properties.ai_estimate_confidence`. Sonde RLS (DO annulé) : `dvf_*` refusées à `authenticated`/`anon`, insertion de snapshot et mise à jour de la confiance refusées. Écart au plan : pas de table `communes_ref` (communes voisines via geo.api.gouv.fr en direct, points échantillonnés à 1 et 2 km).
- **E2–E4, E6 · module Deno** `supabase/functions/_shared/{dvf,estimation}` : nettoyage geo-dvf, comparables par paliers, quartiles pondérés, courbe semestrielle (commune → EPCI → département via l'API tabulaire, `code_parent`), projection, confiance, facteurs non chiffrés ; **sans ajustements** (arbitrage). Explication IA (OpenRouter, `response_format` JSON strict, `data_collection: deny`) avec vérificateur de nombres et gabarit de repli ; raison du repli gardée dans `market_snapshots.error`. Client OpenRouter propre à l'estimation (EPIC-06 a le sien : à converger).
- **E7 · Edge Function** `estimate-property` déployée : lecture sous JWT, 404/409, calcul unique, calcul en arrière-plan (`EdgeRuntime.waitUntil`, réponse 202), cache DVF reprenable fichier par fichier. 48 tests Deno + workflow `edge_functions.yaml`. Essais réels : Chaponost maison 115 m² → 420 000 – 546 000 € (27 comparables à 500 m, confiance 79, ~12 s avec cache) ; Paris 15e appartement 60 m² → 530 000 – 646 000 € (460 comparables, ~25 s au premier chargement). `max_tokens` porté à 1 200 et longueur max à 900 caractères après deux replis observés.
- **E8 · property_repository** : `MarketSnapshot` (+ comparables, facteurs, courbe), `getMarketSnapshot`, `requestEstimate` (`functions.invoke`), `aiEstimateConfidence`.
- **E9 · V8** : `AiEstimateCubit` (calcul, prêt, indisponible, échec + Réessayer, lecture toutes les 3 s pendant 3 min), carte « Non certifiée » avec fiabilité et lien V8b ; V7 demande le calcul après un envoi réussi.
- **E10 · V8b** `lib/seller_tunnel/market/` (route `/vendeur/marche`), captures dans `scratchpad/epic05/`.
- Vérifications : 798 tests Flutter, couverture 100 % (app et `property_repository`), analyse, bloc lint et format propres.
- **2026-10-02 · retours de vérification** : plafond de 3 nouveaux calculs par utilisateur sur 24 h (comptés dans `market_snapshots` joint à `properties.owner_id`, 429 → message dédié dans l'app) ; calcul refusé (409) sans titre de propriété et pièce d'identité non rejetés ; textes libres du vendeur (V6) exclus de l'appel OpenRouter ; distances affichées arrondies à 100 m (en attendant l'arbitrage sur la traçabilité des comparables) ; garde `status = 'running'` pour les calculs abandonnés ; espaces insécables (« 1 an », « 12 mois », « N ans », « : ») ; lien « Voir la synthèse du marché » sur plusieurs lignes en grand texte. Aucune migration nouvelle. 50 tests Deno, fonction redéployée et vérifiée (409 sans documents, 429 après 3 tentatives).
- **2026-10-02 · arbitrage S2 (traçabilité des comparables)** : rue conservée (règle des 3 ventes inchangée), distance arrondie à 100 m et **année de vente seulement** partout : la fonction stocke et renvoie `sold_year` au lieu de `sold_on` (aucun résultat existant à reprendre), l'IA reçoit l'année des dernières ventes, V8b affiche « vendue en 2025 ». Fonction redéployée après les tests Deno.
- **2026-10-02 · arbitrage « la fraîcheur prime »** : paliers recalculés — fenêtres 24 → 36 → 60 mois, et dans chaque fenêtre rayons 500 m → 1 → 2 → 5 → 10 → 20 km ; premier palier à 10 ventes, sinon le palier le plus fourni (le plus récent et le plus proche à égalité), < 5 → pas d'estimation. Plus de palier « commune » (les ventes sans coordonnées sont ignorées). Chargement progressif : anneaux 2 / 5 / 10 / 20 km (communes trouvées par points échantillonnés jusqu'à 2 km, puis par les listes de communes des départements traversés, centre à ≤ rayon + 3 km), 3 dernières années, puis 2 années plus anciennes seulement si 20 km sur 3 ans reste insuffisant ; budget de chargement 100 s. Confiance : facteur de rayon (1 → 0,2) et facteur de période (1 / 0,8 / 0,5). L'IA reçoit `periode_annees`, le gabarit dit « sur les N dernières années ». App : `MarketSnapshot.isSearchWidened` (≥ 5 km ou > 2 ans) → mention sur V8 et bandeau sur V8b. 57 tests Deno (dont un jeu « rural clairsemé »). Essai réel à La Courtine (23) : 18 ventes à 10 km sur 2 ans, 103 000 – 148 000 €, confiance 45, ~35 s au premier chargement. Chaponost : 500 m sur 2 ans suffit (18 ventes, 419 000 – 540 000 €).
