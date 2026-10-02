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

## Corriger une erreur

Une certification ne se modifie pas depuis l’application. Pour corriger un avis de valeur, mettre à jour la ligne `public.valuations` concernée dans le SQL Editor (l’application lit toujours le plus récent, par `certified_at`).

Pour annuler une certification faite par erreur :
1. supprimer la ligne `valuations` ;
2. supprimer le PDF éventuel dans **Storage → valuation-reports** (`<owner id>/<property id>/…`) ;
3. supprimer les notifications du dossier (`delete from public.notifications where property_id = '<property id>' and kind in ('valuation_certified', 'review_started');`, la seconde seulement si le dossier n’a pas vraiment été pris en examen) ;
4. remettre le dossier à `in_review` (`update public.properties set status = 'in_review' where id = '<property id>';`).
