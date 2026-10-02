# EPIC-05 · Estimation non certifiée (tendance de prix)

**Objectif** : donner au vendeur, dès l'envoi de son dossier, une première estimation **non certifiée** de son bien, en croisant les ventes réelles (DVF) et la tendance du prix au m² de son secteur. L'expert reste seul à certifier la valeur.
**Statut** : 🚧 v1 livrée (back-end, V8, V8b) — à valider sur iPhone et en design

Plan : `docs/plans/2026-10-01-estimation-non-certifiee.md` (section « Arbitrages du porteur de projet » et journal d'exécution).

Règles validées :
- calcul **une seule fois, à l'envoi** du dossier (pas de recalcul ; l'expert certifie ensuite) ;
- **sans ajustements en v1** : prix au m² du secteur × surface habitable, fourchette tirée des quartiles ;
- ventes comparables avec **la rue sans le numéro**, rue affichée **seulement si ≥ 3 ventes** y figurent (sinon « Secteur proche »), **distance arrondie à 100 m** et **année de vente seulement** (pas de mois), y compris dans le résultat stocké et les faits envoyés à l'IA ;
- **moins de 5 ventes comparables → pas d'estimation**, message « l'expert s'en charge » ;
- l'IA (Claude via OpenRouter) rédige seulement l'explication, aucun chiffre ;
- libellé **« Non certifiée »** sur la carte V8 et l'écran V8b.

## US-05.1 · Données DVF côté serveur ✅
*En tant que porteur de projet, je veux que les ventes DVF du secteur soient chargées et nettoyées automatiquement.*
- ✅ Fichiers geo-dvf par commune téléchargés, regroupés par mutation, stockés dans `dvf_sales` (rue sans numéro).
- ✅ Écartées : multi-lots (ou avec local commercial), dépendances seules, €/m² hors 500–25 000 € puis hors 1,5 × écart interquartile ; compteurs dans `dvf_sources.rows_dropped`.
- ✅ Revalidation `ETag` ≤ 1 fois / 7 jours ; fichier absent enregistré comme vide.
- ✅ Tables `dvf_*` inaccessibles à `anon` / `authenticated` (sonde RLS faite).
- ✅ Communes à ≤ 2 km via geo.api.gouv.fr (arrondissements à Paris / Lyon / Marseille).

## US-05.2 · Calcul unique de la tendance ✅
*En tant que vendeur, je veux une fourchette indicative calculée à l'envoi de mon dossier à partir de ventes réelles proches.*
- ✅ `estimate-property` : propriétaire seulement (JWT, sinon 404), dossier envoyé / en examen avec titre de propriété et pièce d'identité non rejetés (sinon 409).
- ✅ Plafond de coût : 3 nouveaux calculs par utilisateur sur 24 h (429, message « Trop de demandes de calcul aujourd'hui » dans l'app, sans « Réessayer »).
- ✅ Terrain / autre, surface ou localisation manquante, Alsace-Moselle / Mayotte → résultat définitif `insufficient` avec une raison.
- ✅ Comparables même type, surface ± 30 %, 500 m → 1 km → 2 km → commune (3 ans) → commune (5 ans).
- ✅ < 5 comparables → pas d'estimation, pas d'appel IA.
- ✅ Médiane / quartiles pondérés (proximité, ancienneté) du €/m² projeté à aujourd'hui (courbe semestrielle commune, sinon EPCI / département des Statistiques DVF ; dérive ± 5 %/an max).
- ✅ Fourchette au millier (± 5 % à ± 20 %), indice de confiance 0–100.
- ✅ Calcul unique (index uniques), en arrière-plan (202) ; un calcul bloqué > 150 s est abandonné.
- ✅ 48 tests Deno (dont les ventes réelles de Chaponost) + workflow CI `edge_functions.yaml`.

## US-05.3 · Explication rédigée par l'agent ✅
- ✅ 3 phrases courtes, vouvoiement, rappel « non certifiée ».
- ✅ Tout nombre du texte doit venir des chiffres fournis, sinon texte gabarit.
- ✅ Panne / délai (15 s) d'OpenRouter → gabarit ; l'estimation n'est jamais bloquée.
- ✅ Aucune donnée personnelle ni texte libre du vendeur (atouts / points de vigilance V6) envoyé : seulement des faits structurés ; modèle réglable (`OPENROUTER_MODEL_ESTIMATE`, défaut `anthropic/claude-opus-5.5`).

## US-05.4 · Tendance IA sur V8 ✅
- ✅ L'envoi V7 demande le calcul sans attendre ; V8 le redemande seulement si aucune tentative n'existe.
- ✅ « Calcul de votre tendance de prix… » puis la carte (fourchette, médiane, fiabilité, date, « Non certifiée ») sans relancer l'app.
- ✅ < 5 ventes : « Trop peu de ventes comparables… l'expert s'en charge » ; autre raison : « Pas de tendance automatique… » ; échec : « Réessayer » (seul moyen de relancer).
- ✅ Pas d'actualisation ; carte masquée pour un brouillon ou un dossier certifié.
- ✅ « Voir la synthèse du marché » quand l'estimation existe.

## US-05.5 · Synthèse du marché (V8b) ✅
- ✅ Route autonome `/vendeur/marche`, lecture seule, retour vers V8.
- ✅ Synthèse, bande Q1 / médiane / Q3 avec le bien, base de calcul (ventes, rayon ou commune, période).
- ✅ Tuiles « Ventes sur 12 mois » et « Évolution des prix sur 1 an ».
- ✅ 3 ventes comparables (rue ou « Secteur proche », année, distance arrondie à 100 m) + « Voir les N ventes » ; facteurs + / − ; explication de l'agent ; sources DVF / Etalab / Licence Ouverte avec le mois des dernières ventes.
- ✅ Masqués en v1 : Partager, rapport complet (V9b), délai de vente, annonces, « Une question ? ».
- ✅ fr / en / es ; 100 % de couverture.

## À valider / suite
- 📋 Design : ligne « Fiabilité » (V8), carte « En résumé » et tuiles à 2 colonnes (V8b).
- 📋 Courbe semestrielle (stockée) : graphique sur V9b ou réservé à l'expert ?
- 📋 Converger le client OpenRouter avec celui d'EPIC-06.
