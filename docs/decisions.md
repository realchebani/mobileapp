# Décisions produit et techniques

Journal des arbitrages du porteur de projet, du plus récent au plus ancien. Chaque décision renvoie à l'epic ou au plan concerné.

| Date | Décision | Contexte |
|---|---|---|
| 2026-10-01 | **IA via OpenRouter**, modèle **Claude (Anthropic)** ; clé stockée uniquement dans les secrets Supabase (`OPENROUTER_API_KEY`) | EPIC-06 |
| 2026-10-01 | **Estimation non certifiée** : croisement ventes DVF + tendance du prix au m², **sans annonces en v1** (pas de source ouverte légale) ; affichée sur la carte « Tendance IA » (V8) et l'écran « Synthèse du marché » (V8b) | EPIC-05 |
| 2026-10-01 | Ordre de la feuille de route : tunnel vendeur à l'écran → estimation non certifiée + voix / agent IA → Dashboard vendeur (V9+) | — |
| 2026-10-01 | V7 : chaque document peut être **scanné ou importé** ; scan **multipage** regroupé en un PDF ; **diagnostics facultatifs** ; envoi bloqué seulement sans **titre de propriété** ou **pièce d'identité** | EPIC-04 (US-04.8, US-04.11) |
| 2026-10-01 | V4b : **plusieurs moyens de chauffage** possibles | EPIC-04 (US-04.10) |
| 2026-10-01 | V5c : **surface habitable et annexes** distinguées (garage, cellier, sous-sol, buanderie en annexe) | EPIC-04 (US-04.6) |
| 2026-10-01 | V6 : la note libre est destinée aux **futurs visiteurs** | EPIC-04 (US-04.7) |
| 2026-10-01 | Validés : adaptation appartement / terrain de V4b, score de transparence 70 % documents / 30 % réponses, libellés du bruit, choix V1–V3 (terrain sans « Construit ? », « Autre » + précision, montants 1 000 € – 100 M€, suppression dans la fiche) | EPIC-04 |
| 2026-10-01 | **Carte : Mapbox** (licence propriétaire, exclue du contrôle de licences) — en attente du jeton public | EPIC-04 (V2) |
| 2026-10-01 | CI : `gtk` (Linux, MPL-2.0) et `pubspec_lock_parse` (outil de dev) exclus du contrôle de licences | CI |
| 2026-09-30 | Tunnel vendeur **à l'écran d'abord** (voix, scan AR et OCR reportés) ; adresse et cadastre via les services publics IGN / Géoplateforme | EPIC-04 |
| 2026-09-30 | Connexion par **lien magique** (pas de SMTP pour l'instant) | EPIC-03 |
| 2026-09-30 | Bundle ID `fr.realesty.mobile` ; compte Apple gratuit ; français langue de référence | EPIC-01 |

## Backlog (non planifié)

- Refonte graphique de l'aperçu des données V8 (US-04.12).
- Carte Mapbox en V2 (jeton public à fournir).
- E-mails de connexion en français via un SMTP (Brevo) — nécessaire avant d'ouvrir l'app à d'autres testeurs.
- Projet Supabase distinct pour la production.
- Version Android (permissions, scanner ML Kit).
- Dashboard vendeur (V9+), tunnel acquéreur (A1+), espace agences (P1+).
