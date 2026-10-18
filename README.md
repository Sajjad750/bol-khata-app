# Bol Khata

Bol Khata is a Flutter app for shopkeepers to keep customer credit and payment records. It saves customer and ledger changes in an on-device SQLite database. The current voice flow sends recordings to Groq, so voice entry requires internet. Cloud upload uses Supabase when a phone-linked session is available. Cloud restore and on-device speech are planned work.

## Local setup

1. Install [Flutter 3.44.8](https://github.com/flutter/flutter/releases/tag/3.44.8). Its bundled Dart SDK satisfies the project's Dart 3.12.2 requirement. For Android builds, install the Android SDK and run `flutter doctor`.
2. Copy `.env.example` to `.env`. Leave the placeholders for local database work and tests. Add your own Groq and Supabase credentials only when testing those services. `.env` is ignored by Git; do not commit real keys.
3. Run `flutter pub get --enforce-lockfile`, `flutter analyze`, and `flutter test`.
4. For an Android test build, run `flutter build apk --debug`.

The asset declaration currently requires `.env` to exist at build time even when the app runs without online services. GitHub CI creates it from the placeholder example and never uses production credentials.

## Development

Pull requests and pushes to `main` run [Flutter checks](.github/workflows/flutter-ci.yml): dependency resolution, formatting, analysis, tests and a debug Android build. The workflow uses the same Flutter version as `pubspec.yaml` and a placeholder `.env`.

The [project analysis](PROJECT_ANALYSIS.md) explains the current implementation and risks. The [engineering plan](ENGINEERING_PLAN.md) describes the offline voice experiment, safer ledger and identity design, sync/restore, testing, usability and release steps. Neither document means those planned features are implemented.
