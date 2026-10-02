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
| [EPIC-07](epics/EPIC-07-tableau-de-bord-vendeur.md) | Espace vendeur : tableau de bord & avis de valeur | 🚧 |
| [EPIC-08](epics/EPIC-08-formules-et-mise-en-vente.md) | Formules & mise en vente (mandat de test, annonce dans Realesty) | 📋 |
| [EPIC-11](epics/EPIC-11-coffre-fort-et-compte.md) | Coffre-fort & compte (documents, profil, suppression du compte) | 📋 |
| [EPIC-12](epics/EPIC-12-back-office-expert.md) | Back-office expert (certification web) | 📋 |
| [EPIC-14](epics/EPIC-14-voix-etendue.md) | Voix étendue à tout le tunnel vendeur (dictée de pièces) | 📋 |
| [EPIC-13](epics/EPIC-13-multi-biens.md) | Plusieurs biens & lots de vente | 📋 |
| [EPIC-16](epics/EPIC-16-voix-prioritaire.md) | Voix prioritaire (pré-remplissage inter-étapes, traçabilité expert) | 📋 |
| [EPIC-15](epics/EPIC-15-photos-du-bien.md) | Photos du bien (pièces, IA de vision, lecture de plan) | 🚧 |

## Plans d'implémentation

Chaque chantier commence par un plan, versionné dans [`plans/`](plans/) (`AAAA-MM-JJ-sujet.md`) et mis à jour au fil du codage.

| Date | Plan | Epics |
|---|---|---|
| 2026-09-30 | [Design system & authentification](plans/2026-09-30-design-system-et-authentification.md) | EPIC-02, EPIC-03 |
| 2026-09-30 | [Tunnel vendeur](plans/2026-09-30-tunnel-vendeur.md) · [cahier des charges](plans/2026-09-30-tunnel-vendeur-spec.md) | EPIC-04 |
| 2026-10-01 | [Estimation non certifiée](plans/2026-10-01-estimation-non-certifiee.md) (validé) | EPIC-05 |
| 2026-10-01 | [Voix et agent IA](plans/2026-10-01-voix-et-agent-ia.md) (validé) | EPIC-06 |
| 2026-10-01 | [Parcours vendeur V8b → V19](plans/2026-10-01-parcours-vendeur-v8b-v19.md) (questions ouvertes) | EPIC-07 à EPIC-11 |
| 2026-10-02 | [Voix étendue à tout le tunnel](plans/2026-10-02-voix-etendue.md) (questions ouvertes, après EPIC-13) | EPIC-14 |
| 2026-10-02 | [Plusieurs biens & lots de vente](plans/2026-10-02-multi-biens.md) (validé, livré) | EPIC-13 |
| 2026-10-02 | [Étude : capture visuelle du bien](plans/2026-10-02-capture-visuelle-etude.md) (questions ouvertes) | — |
| 2026-10-03 | [Voix prioritaire](plans/2026-10-03-voix-prioritaire.md) (questions ouvertes, après EPIC-15) | EPIC-16 |
| 2026-10-02 | [Photos du bien](plans/2026-10-02-photos-du-bien.md) (livré, à essayer sur l’iPhone) | EPIC-15 |
| 2026-10-03 | [Formules & mise en vente](plans/2026-10-03-offres-et-mise-en-vente.md) (questions ouvertes) | EPIC-08 |
| 2026-10-03 | [Coffre-fort & compte](plans/2026-10-03-coffre-fort-et-compte.md) (questions ouvertes) | EPIC-11 |
| 2026-10-03 | [Back-office expert](plans/2026-10-03-back-office-expert.md) (questions ouvertes) | EPIC-12 |

## Décisions et backlog

Les arbitrages du porteur de projet et le backlog non planifié sont dans [`decisions.md`](decisions.md).

Procédures d’exploitation : [`runbooks/`](runbooks/) (ex. [certifier un dossier](runbooks/certifier-un-dossier.md)).

## Méthode de travail

- Une branche par chantier et une Pull Request ; CI GitHub verte obligatoire (tests à 100 % de couverture, analyse, licences, orthographe des fichiers Markdown anglais).
- Chaque étape est codée par un agent puis contrôlée par un agent de vérification indépendant (tests, revue de code, rendu comparé aux maquettes) avant commit.
- Les migrations Supabase sont versionnées dans `supabase/migrations/` et appliquées avec `supabase db push`.

Références :
- Design : canvas Claude Design « Realesty · App mobile » — https://claude.ai/artifact/7iUZPTfM8Kf6xrEY4nnS5v
- Guide technique : [`CLAUDE.md`](../CLAUDE.md)
