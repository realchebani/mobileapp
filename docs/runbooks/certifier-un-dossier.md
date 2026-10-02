# Runbook · Mettre un dossier en examen et le certifier

En attendant le back-office web des experts (EPIC-12), l’équipe Realesty certifie un dossier depuis le **SQL Editor** du tableau de bord Supabase (projet « Mobileapp »), avec les fonctions de la migration `20261001162633_valuations_and_notifications.sql`. Ces fonctions ne sont pas appelables depuis l’application (exécution retirée aux rôles `anon` et `authenticated`) : le SQL Editor tourne avec le rôle `postgres`.

## 1. Trouver le dossier

```sql
select p.id, p.owner_id, p.status, p.submitted_at, p.address_label, p.living_area_m2,
       p.ai_estimate_median_eur, pr.first_name
from public.properties p
left join public.profiles pr on pr.id = p.owner_id
where p.status in ('submitted', 'in_review')
order by p.submitted_at;
```

## 1 bis. Voir les photos des pièces et le plan (EPIC-15)

Chaque pièce principale d’une maison, d’un appartement ou d’un bien « Autre » a au moins une photo (règle d’envoi). Les photos sont dans `room_photos`, rangées par pièce (`sort_order` : la première est la photo principale), avec les contrôles faits sur le téléphone (`quality` : luminosité, netteté, inclinaison, défauts) et, si le vendeur a accepté l’IA de vision, ce que le modèle a vu (`analysis` : type de pièce, revêtement, vitrage, constats sans chiffre, objets personnels, personne visible). **L’analyse IA n’est qu’une aide : rien n’est vérifié.**

```sql
select r.name as piece, r.is_main, ph.sort_order, ph.storage_path,
       ph.quality -> 'issues' as defauts,
       ph.analysis -> 'condition_notes' as constats_ia,
       ph.analysis -> 'people_visible' as personne_visible
from public.room_photos ph
join public.rooms r on r.id = ph.room_id
where ph.property_id = '<property id>'
order by r.sort_order, ph.sort_order;
```

Les fichiers sont dans le bucket privé `property-documents` (Storage du tableau de bord) sous `<owner id>/<property id>/photos/<room id>/<photo id>.jpg` : les ouvrir depuis le navigateur de fichiers, ou générer une URL signée (bouton « Get URL »). Un plan lu en V5 est un document `plan` ; ce que l’IA y a lu est dans `property_documents.extracted -> 'plan_reading'` (pièces imprimées, `printed_total_m2`, `total_matches`) et les pièces gardées par le vendeur ont `rooms.source = 'plan'`.

Coût et qualité de l’IA de vision (service role) :

```sql
select kind, model, date_trunc('week', created_at) as semaine, count(*) as appels,
       round(sum(cost_usd), 4) as cout_usd, round(avg(ms)) as ms_moyen,
       count(*) filter (where error is not null) as erreurs
from public.vision_requests
group by 1, 2, 3 order by 3 desc;
```

Changer de modèle sans nouvelle version de l’app : `supabase secrets set OPENROUTER_MODEL_VISION=<modèle>` (photos) et, au besoin, `OPENROUTER_MODEL_PLAN=<modèle>` (plans).

Valeurs de `vision_requests.error` : `null` (réussi), `locked` (dossier envoyé pendant l’analyse : payé mais non enregistré), `duplicate` (résultat déjà enregistré par un autre appel : aucun appel au modèle), `in_progress` (en cours, ou appel interrompu : au-delà de 2 minutes — 3 pour un plan — une nouvelle analyse de la même cible est permise), `invalid_output`, `upstream`, `failed`, `missing_file`, `too_large`, `unsupported`. Deux appels simultanés pour la même photo (ou le même plan) ne coûtent qu’une analyse : le second attend le résultat du premier (20 s au plus, puis 409 `busy`).

Une fois le dossier envoyé (`submitted`), le vendeur ne peut plus supprimer la **dernière photo d’une pièce principale** (déclencheur `room_photos_keep_main_photo`, erreur `room_photo_required`) ; l’équipe le peut depuis le SQL Editor (sans JWT), par exemple pour retirer une photo où une personne est visible — prévenir alors le vendeur.

## 1 ter. Relire la fiche de remplissage (EPIC-16)

Avant de certifier, relire d’où vient chaque valeur (dicté, dit à une autre étape, saisi, extrait, externe), la phrase d’origine et les valeurs « à vérifier », puis, si besoin, le fil de conversation : [fiche-de-remplissage.md](fiche-de-remplissage.md).

```sql
select step, label_fr, value, source, quote, confirmed, confirmation, verified
from public.staff_fill_sheet('<property id>') order by sort_order;
```

## 2. Le passer en examen (facultatif)

```sql
select public.staff_start_review('<property id>');
```

Le dossier passe à `in_review` (il n’est plus modifiable par le vendeur) et le vendeur reçoit la notification « Un expert analyse votre dossier », qui ouvre ce bien (`/vendeur/biens/<property id>`).

Lots de vente (EPIC-13) : dès qu’un bien d’un lot est `in_review` ou `certified`, le lot est figé (plus d’ajout / retrait de bien, ni de changement de mode de vente). Chaque bien du lot est certifié séparément ; pour voir les lots d’un vendeur : `select * from public.property_lots where owner_id = '<user id>';` et `select id, property_type, status, lot_id from public.properties where owner_id = '<user id>';`.

## 3. Certifier avec le rapport structuré

`staff_certify_property(property_id, valuation)` accepte un dossier `submitted` ou `in_review`, enregistre l’avis de valeur, passe le dossier à `certified` et envoie la notification « Votre avis de valeur certifié est disponible » (qui ouvre le rapport V9b du bien : `/vendeur/biens/<property id>/rapport`). Pour un garage, une dépendance ou un local, `price_m2_eur` n’est calculé que si une surface habitable existe : le renseigner à la main au besoin.

Champs obligatoires : `value_eur`, `low_eur`, `high_eur` (avec `low ≤ value ≤ high`) et `expert_display_name`. Tout le reste est facultatif : une section vide est masquée dans l’application.

Valeurs par défaut : `price_m2_eur` = valeur ÷ surface habitable ; `ai_trend_eur` = tendance IA calculée à l’envoi ; `certified_at` = maintenant ; `valid_until` = certification + 3 mois.

Règles de rédaction :
- ventes comparables : **la rue sans le numéro** (« rue Lucien Cozon ») ;
- montants en euros entiers, sans espace ni symbole ;
- `provenance` d’une ligne de la fiche technique : `declared`, `document`, `external` ou `verified` ;
- `kind` d’une ligne de montant : `base` (point de départ), `line` (ajustement, affiché signé), `total` (résultat, en gras), `control` (contrôle, en gris).

Modèle (valeurs d’exemple de la maquette) :

```sql
select public.staff_certify_property('<property id>', $json$
{
  "value_eur": 525000,
  "low_eur": 505000,
  "high_eur": 545000,
  "estimated_delay_weeks": 8,
  "expert_display_name": "Julien M.",
  "expert_initials": "JM",
  "method_steps": [
    {"label": "Tendance IA", "detail": "avant la visite", "amount_eur": 518000},
    {"label": "Analyse des méthodes", "detail": "ventes 70 % · concurrence 30 %", "amount_eur": 521000},
    {"label": "Constat de visite", "detail": "luminosité, état relevé", "amount_eur": 4000, "is_delta": true},
    {"label": "Valeur certifiée", "detail": "arrondie par l’expert", "amount_eur": 525000}
  ],
  "reasons": [
    {"positive": true, "text": "Piscine, garage-atelier et bureau fermé réunis : une combinaison rare à Chaponost"},
    {"positive": false, "text": "Un léger vis-à-vis et une salle de bain à rafraîchir, intégrés au prix"}
  ],
  "delay_curve": [
    {"price_eur": 505000, "label": "≈ 5 semaines"},
    {"price_eur": 525000, "label": "≈ 8 semaines"},
    {"price_eur": 555000, "label": "plus de 5 mois"},
    {"price_eur": 585000, "label": "très peu de visites"}
  ],
  "expert_quote": "Ce bien réunit ce que les familles cherchent à Chaponost…",
  "description": "Maison familiale de 115 m² sur 540 m² de terrain…",
  "technical_sheet": [
    {"label": "Construction", "value": "1998 · parpaing", "provenance": "declared"},
    {"label": "Toiture", "value": "Tuiles · refaite en 2016", "provenance": "document"},
    {"label": "Assainissement", "value": "Tout-à-l’égout", "provenance": "external"},
    {"label": "DPE", "value": "Classe C · 2024", "provenance": "verified"}
  ],
  "comparables": [
    {"street": "rue Lucien Cozon", "sold_on": "2025-10-01", "area_m2": 107, "land_m2": 576, "price_eur": 457000},
    {"street": "rue des Fauvettes", "sold_on": "2025-03-01", "area_m2": 99, "land_m2": 987, "price_eur": 674831, "excluded": true}
  ],
  "comparables_note": "Vente rue des Fauvettes écartée (bien atypique). Médiane retenue : 4 250 €/m².",
  "competitors_summary": "19 maisons de 100 à 130 m² en vente · 0 avec piscine et garage",
  "competitors": [
    {"label": "T5 · 113 m²", "price_eur": 429000, "note": "Comparable direct, sans piscine ni garage", "days_online": 114, "retained": true},
    {"label": "T6 · 120 m²", "price_eur": 355000, "note": "Maison de ville, segment différent", "days_online": 54, "retained": false}
  ],
  "risks_note": "aucun risque d’inondation recensé, aucune cavité à moins de 500 m (Géorisques, 25/09/2026).",
  "adjustments": [
    {"label": "Base ventes signées · 4 250 €/m² × 115 m²", "amount_eur": 489000, "kind": "base"},
    {"label": "Piscine enterrée en bon état", "amount_eur": 20000},
    {"label": "Vis-à-vis léger", "amount_eur": -5000},
    {"label": "Méthode 1 corrigée", "amount_eur": 528000, "kind": "total"}
  ],
  "method_summary": [
    {"label": "Ventes signées · 70 %", "amount_eur": 528000},
    {"label": "Concurrence actuelle · 30 %", "amount_eur": 505000},
    {"label": "Pondération des méthodes", "amount_eur": 521000, "kind": "total"},
    {"label": "Contrôle : tendance IA", "amount_eur": 518000, "kind": "control"}
  ],
  "works_label": "Salle de bain à rafraîchir",
  "works_estimate_eur": 5000,
  "sources": "Base DVF · DGFiP · Audit Realesty · Géorisques · Visite de l’expert"
}
$json$::jsonb);
```

La fonction renvoie l’identifiant de l’avis de valeur (utile pour l’étape 4). En cas d’erreur (dossier introuvable, déjà certifié, champ obligatoire manquant), rien n’est enregistré.

## 4. Joindre le PDF (facultatif)

1. Dans **Storage → valuation-reports**, déposer le PDF sous `<owner id>/<property id>/avis-de-valeur.pdf` (le premier dossier doit être l’identifiant du propriétaire : c’est lui qui ouvre l’accès en lecture).
2. Lier le fichier à l’avis de valeur :

```sql
select public.staff_attach_valuation_report(
  '<valuation id>', '<owner id>/<property id>/avis-de-valeur.pdf', 11::smallint
);
```

La fonction refuse un chemin qui ne commence pas par `<owner id>/<property id>/` de l’avis de valeur, ou un fichier absent du bucket : déposer le PDF d’abord, au bon endroit.

Le bouton « Télécharger le rapport (PDF · 11 pages) » apparaît alors sur V9b.

## 5. Fichiers orphelins (ménage du stockage, facultatif)

Un fichier du bucket `property-documents` peut rester sans ligne en base : envoi dont la ligne a été refusée et dont la suppression a échoué, suppression d’une photo ou d’un document dont le fichier n’a pas pu être effacé, bien supprimé pendant une coupure réseau. Ces fichiers ne sont visibles par personne dans l’app, mais ce sont des données personnelles (pièces d’identité, photos) : faire le ménage **une fois par mois** environ.

1. Lister les orphelins (SQL Editor, rôle service ; les fichiers de moins de 24 h sont ignorés, un envoi peut être en cours) :

```sql
select path, size_bytes, created_at, property_exists
from public.staff_orphan_files()  -- ou staff_orphan_files(interval '7 days')
order by created_at;
```

`property_exists = false` : le bien n’existe plus (brouillon supprimé) ; `true` : fichier d’un bien existant sans document ni photo correspondant (`property_documents`, plans compris, et `room_photos`). La fonction ne supprime rien.

2. Vérifier la liste (un fichier d’un bien en examen ou certifié se regarde avant d’être supprimé), puis supprimer les fichiers **par l’API Storage** — jamais par `delete from storage.objects`, qui laisserait le fichier en place :
   - tableau de bord : **Storage → property-documents**, sélectionner les fichiers, « Delete » ;
   - ou en ligne de commande, depuis le dépôt lié : `supabase storage rm --linked --experimental "ss:///property-documents/<path>" …` (un chemin par fichier listé).

3. Relancer la requête : elle ne doit plus renvoyer ces chemins.

## Corriger une erreur

Une certification ne se modifie pas depuis l’application. Pour corriger un avis de valeur, mettre à jour la ligne `public.valuations` concernée dans le SQL Editor (l’application lit toujours le plus récent, par `certified_at`).

Pour annuler une certification faite par erreur :
1. supprimer la ligne `valuations` ;
2. supprimer le PDF éventuel dans **Storage → valuation-reports** (`<owner id>/<property id>/…`) ;
3. supprimer les notifications du dossier (`delete from public.notifications where property_id = '<property id>' and kind in ('valuation_certified', 'review_started');`, la seconde seulement si le dossier n’a pas vraiment été pris en examen) ;
4. remettre le dossier à `in_review` (`update public.properties set status = 'in_review' where id = '<property id>';`).
