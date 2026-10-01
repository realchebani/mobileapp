# Realesty

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

Realesty is a French real-estate mobile app: sellers sell for 1 % with an AI-audited dossier validated by a real-estate expert, buyers find homes that fit their lifestyle. Flutter (iOS first) + Supabase.

- **Product & project documentation (French):** [`docs/`](docs/README.md) — epics, user stories, implementation plans, product decisions.
- **Technical guide (architecture, commands, conventions):** [`CLAUDE.md`](CLAUDE.md).
- **Design source of truth:** Claude Design canvas "Realesty · App mobile".

## Getting started

Requirements: Flutter 3.47, Xcode (iOS), the Supabase CLI (logged in and linked to the project).

```sh
flutter pub get
flutter gen-l10n

# Run a flavor (development | staging | production)
flutter run --flavor development --target lib/main_development.dart --dart-define-from-file=config/development.json
```

`config/<flavor>.json` holds the public Supabase URL and publishable key and the magic-link redirect URL of each flavor. Server secrets (e.g. `OPENROUTER_API_KEY`) live only in Supabase secrets.

## Tests and quality

```sh
very_good test --coverage --test-randomize-ordering-seed random   # 100 % line coverage is enforced in CI
(cd packages/property_repository && dart test)                    # each local package has its own tests
flutter analyze
dart run bloc_tools:bloc lint .
dart format .
```

CI (GitHub Actions) also runs a Markdown spell check, the tests of every package in `packages/` and a dependency license check (MIT, BSD and Apache only).

## Repository layout

| Path | Content |
|---|---|
| `lib/` | App: `app/` (bootstrap, router), `ui/` (design system), one folder per feature (`login/`, `role/`, `seller_tunnel/`…) |
| `packages/` | Data layer: `auth_repository`, `profile_repository`, `property_repository`, `geo_repository` |
| `supabase/` | Linked Supabase project: `config.toml`, SQL migrations |
| `config/` | Per-flavor public configuration |
| `docs/` | Product documentation (French) |

[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
