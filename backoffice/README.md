# Realesty back-office

Internal Flutter web app (EPIC-12) for the Realesty team and partner experts: queue of the dossiers sent by sellers, dossier review (answers with provenance, photos, documents, voice thread, market snapshot), structured valuation form, certification, team and audit log.

Security model, roles and the first administrator: [docs/runbooks/back-office.md](../docs/runbooks/back-office.md). The browser only gets the Supabase publishable key; every read and write goes through the `bo_*` SQL functions (role and MFA checked by the database) and files through the `bo-files` Edge Function.

## Run locally

```sh
cd backoffice
flutter run -d chrome --web-port 3000 --dart-define-from-file=config/development.json
```

Port 3000 matches the Supabase `site_url`, so magic links come back to the local app. `DEV_PASSWORD_LOGIN` (development config only) shows a password sign-in for test accounts.

## Checks

```sh
flutter analyze
dart run bloc_tools:bloc lint .
very_good test --coverage --min-coverage 100
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/production.json
```

Strings are French only (`lib/l10n/arb/app_fr.arb`, then `flutter gen-l10n`).

## Hosting

Not deployed yet: see the hosting section of the runbook. The `backoffice_deploy` workflow is manual and disabled until the owner provides the hosting account and the domain.
