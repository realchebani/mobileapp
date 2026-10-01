# Documentation Realesty

Suivi des travaux sous forme d'**epics** et de **user stories**. Chaque epic est un fichier dans [`epics/`](epics/) ; chaque user story y a un identifiant `US-XX.Y`, des critères d'acceptation et un statut.

Statuts : ✅ Terminé · 🚧 En cours · 📋 À faire

| Epic | Titre | Statut |
|---|---|---|
| [EPIC-01](epics/EPIC-01-socle-projet.md) | Socle du projet & installation sur iPhone | ✅ |
| [EPIC-02](epics/EPIC-02-design-system.md) | Design system | ✅ |
| [EPIC-03](epics/EPIC-03-authentification.md) | Authentification par lien magique | ✅ |
| [EPIC-04](epics/EPIC-04-tunnel-vendeur.md) | Tunnel vendeur (audit du bien) | ✅ (US-04.12 au backlog) |
| [EPIC-05](epics/EPIC-05-estimation-non-certifiee.md) | Estimation non certifiée (tendance de prix) | 📋 |
| [EPIC-06](epics/EPIC-06-voix-et-agent-ia.md) | Voix et agent IA | 📋 |

## Plans d'implémentation

Chaque chantier commence par un plan, versionné dans [`plans/`](plans/) (`AAAA-MM-JJ-sujet.md`) et mis à jour au fil du codage.

| Date | Plan | Epics |
|---|---|---|
| 2026-09-30 | [Design system & authentification](plans/2026-09-30-design-system-et-authentification.md) | EPIC-02, EPIC-03 |
| 2026-09-30 | [Tunnel vendeur](plans/2026-09-30-tunnel-vendeur.md) · [cahier des charges](plans/2026-09-30-tunnel-vendeur-spec.md) | EPIC-04 |
| 2026-10-01 | [Estimation non certifiée](plans/2026-10-01-estimation-non-certifiee.md) (validé) | EPIC-05 |
| 2026-10-01 | [Voix et agent IA](plans/2026-10-01-voix-et-agent-ia.md) (validé) | EPIC-06 |
| 2026-10-01 | [Parcours vendeur V8b → V19](plans/2026-10-01-parcours-vendeur-v8b-v19.md) (questions ouvertes) | EPIC-07 à EPIC-11 |

## Décisions et backlog

Les arbitrages du porteur de projet et le backlog non planifié sont dans [`decisions.md`](decisions.md).

## Méthode de travail

- Une branche par chantier et une Pull Request ; CI GitHub verte obligatoire (tests à 100 % de couverture, analyse, licences, orthographe des fichiers Markdown anglais).
- Chaque étape est codée par un agent puis contrôlée par un agent de vérification indépendant (tests, revue de code, rendu comparé aux maquettes) avant commit.
- Les migrations Supabase sont versionnées dans `supabase/migrations/` et appliquées avec `supabase db push`.

Références :
- Design : canvas Claude Design « Realesty · App mobile » — https://claude.ai/artifact/7iUZPTfM8Kf6xrEY4nnS5v
- Guide technique : [`CLAUDE.md`](../CLAUDE.md)
