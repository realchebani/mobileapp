# EPIC-01 · Socle du projet & installation sur iPhone

**Objectif** : disposer d'un projet Flutter Realesty configuré (identité, langue, backend) et installable sur l'iPhone du porteur de projet.
**Statut** : ✅ Terminé

## US-01.1 · Identité de l'application ✅
*En tant que porteur de projet, je veux que l'app s'appelle Realesty avec un identifiant propre, afin de pouvoir l'installer et, plus tard, la publier.*
- [x] Bundle ID / applicationId `fr.realesty.mobile` (flavors `.dev`, `.stg`) sur iOS, Android, macOS, Windows.
- [x] Nom affiché « Realesty », « [DEV] Realesty », « [STG] Realesty ».

## US-01.2 · Français comme langue de référence ✅
*En tant qu'utilisateur francophone, je veux une app en français par défaut.*
- [x] `app_fr.arb` est le modèle des traductions ; `fr` est la langue de repli (`preferred-supported-locales`).
- [x] `fr` déclaré dans `CFBundleLocalizations` (iOS). Anglais et espagnol conservés en secondaire.

## US-01.3 · Installation sur iPhone ✅
*En tant que porteur de projet, je veux installer l'app sur mon iPhone pour la tester en conditions réelles.*
- [x] Signature automatique avec l'équipe personnelle Apple (compte gratuit : l'app expire au bout de 7 jours).
- [x] Build release du flavor development installé et lancé sur l'iPhone 14 Plus.
- [x] Procédure documentée dans `CLAUDE.md`.

## US-01.4 · Connexion au backend Supabase ✅
*En tant que développeur, je veux que l'app soit reliée à Supabase, avec une config par flavor.*
- [x] Projet Supabase « Mobileapp » (eu-west-1) relié au dépôt (`supabase/`).
- [x] `config/{development,staging,production}.json` (URL, clé publique, URL de retour d'auth) passés via `--dart-define-from-file`.
- [x] `Supabase.initialize` au démarrage (`lib/bootstrap.dart`).
- [ ] Projet Supabase distinct pour la production (à faire avant les premiers vrais utilisateurs).
