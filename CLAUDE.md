# Mekuru (めくる)

Japanese-first EPUB and manga reader. Flutter, **Android-only** — `firebase_options.dart` throws on web/desktop.

## Build & test commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift + riverpod + environment_config codegen
dart run build_runner watch --delete-conflicting-outputs   # codegen, watch mode
flutter analyze                                            # static analysis
flutter test                                               # unit tests (in-memory Drift)
flutter test test/path/to/file_test.dart                   # single test
dart format lib test integration_test
flutter run                                                # device/emulator
```

Run codegen after editing any `@riverpod`, `@DriftDatabase`, or `environment_config.yaml`.

**Sentry**: local builds work without it. To enable, run `flutter pub run environment_config:generate --sentryDsn=<dsn> --sentryEnvironment=development` once. This writes `lib/config/environment_config.dart`.

## Before committing

1. `flutter analyze lib test` — **must be clean.** CI fails on info-level deprecation warnings too.
2. `flutter test` — must pass.
3. For user-facing changes, bump `version:` in `pubspec.yaml` (minor for `feat:`, patch for `fix:`).
4. Never add `Co-Authored-By:` trailers to commits.

## Conventions

- **Commits**: conventional prefix — `feat(scope): …`, `fix(scope): …`, `chore: …`, `refactor(scope): …`. CI / release tooling depends on it.
- **Layout**: feature-first under `lib/features/<feature>/{data,presentation}/`. `data/` has `models|repositories|services`; `presentation/` has `providers|screens|widgets`. Shared infra in `lib/core/`.
- **State**: Riverpod with codegen. The global `databaseProvider` is created once in `lib/main.dart` — **never instantiate `AppDatabase` elsewhere** in app code. Tests use the shared `createTestDatabase()` helper from `test/shared/test_database.dart`, which returns `AppDatabase(NativeDatabase.memory())`.
- **Pure-logic files** (e.g. `reader_interaction_logic.dart`, `compound_word_resolver.dart`) must stay free of Flutter UI/widget imports so they remain unit-testable (`flutter/foundation.dart` for `debugPrint` is the accepted ceiling).
- **Telemetry**: `lib/core/services/usage_telemetry.dart` (Sentry-backed, fire-and-forget). **Never** put book titles, file names, user text, or looked-up words in telemetry messages or attributes.

## Database — Drift, append-only migrations

Schema version lives in `lib/core/database/database_provider.dart` (`schemaVersion`, currently 22) with the tables defined inline. Migrations live in the `MigrationStrategy.onUpgrade` block as cumulative `if (from < N) { … }` conditions; additionally, a `beforeOpen` repair pass (`_repairMissingColumns`) re-adds a few columns (the v18/v20 ones) for installs that predate them.

**YOU MUST** make schema changes append-only: add columns/tables, never drop or rename them on an existing version. Bump `schemaVersion` and add a new `if (from < N)` block. Reckless edits break installed users' data — there is no rollback.

In-memory test databases skip migrations entirely (they start at the latest schema). `test/database_migration_test.dart` exercises real file-backed migrations in `flutter test`; integration tests cover the rest.

`PRAGMA foreign_keys` is **OFF** app-wide — cascade deletes are enforced in repository code (e.g. collections), never rely on DB-level cascades. Newer tables: `ReadingSessions`/`WordEvents` (stats, v19), `Collections`/`BookCollections` (v21; per-collection `position` in v22).

## Japanese text pipeline

- **MeCab**: singleton at `MecabService.instance`, initialized in `main.dart`. IPADIC is bundled at `assets/ipadic/` and copied to `applicationDocumentsDirectory` on first launch. UniDic-lite is optionally **downloaded** by the user; `init()` always starts on IPADIC, then a background upgrade swaps in UniDic-lite and silently stays on IPADIC if that fails.
- **Compound words**: greedy longest-match up to 5 tokens (`maxTokenSpan = 5`) against the *enabled* dictionary set.
- **Dictionary queries**: always join `DictionaryMetas` and filter by `isEnabled`. Disabled dictionaries must never surface results.
- **Glossaries**: stored as raw JSON strings in Drift — no type converters. Parse on read.
- **Glossary FTS**: `dictionary_entries_fts` (FTS5) is synced by triggers built from a single DDL map in `database_provider.dart`. Two creation paths (open-time ensure, bulk import) must never construct different triggers.
- **`searchText`**: lowercased plain-text projection of `glossaries` that FTS tokenizes — any writer that updates `glossaries` must refresh `searchText` too.

## Reader / EPUB viewer

- `assets/epub_viewer/reader_bridge.js` — hand-written bridge that talks to Dart via `window.flutter_inappwebview.callHandler(...)`. Owns vertical text, margins, furigana injection, word tapping.
- `assets/epub_viewer/epub.js` — **vendored** epub.js, locally modified. Before editing it, search for `[MEKURU PATCH]` — those markers flag every place upstream behavior is overridden (vertical-axis forcing, queue error handling, missing-manifest-entry skipping, etc.). Don't re-vendor without porting the patches.
- Don't change the bridge's message protocol without updating the matching Dart handlers in the reader feature.

## Android / native

- **`libc++_shared.so` workaround**: `mecab_for_flutter`'s native_assets hook fails on GitHub-hosted runners, so we bundle the lib manually via a `jniLibs` source set in `android/app/build.gradle.kts` (search `bundledLibCppSharedJniLibsDir`). **Do not remove** without verifying CI Android builds still link.
- **Firebase**: `lib/firebase_options.dart` is committed. `android/app/google-services.json` is required for local Android builds and is in the repo.
- **OCR billing / Pro**: validated server-side by the `billingApiV2` Cloud Function. Never bypass token validation or treat the client-side `proUnlockedProvider` as ground truth — round-trip the server.
- **AnkiDroid integration** is Android-intent-based; do not call from non-Android code paths.

## CI / release workflows

`.github/workflows/build-release.yml` produces the Play artifact, plus a second `parallel` flavor APK (`--dart-define=PARALLEL_BUILD=true`, side-by-side install for testers). `scripts/verify_native_libs.py` gates every artifact — it asserts the MeCab native libs actually made it into the build. Two gotchas have bitten this workflow repeatedly:

- **AAB output path includes the flavor.** With `--flavor X`, AGP writes the bundle to `build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab` — e.g. `bundle/playRelease/app-play-release.aab`. APKs are flat (`flutter-apk/app-<flavor>-release.apk`), but bundles are not. Any time you change the flavor flag, update every `bundle/...` path in the workflow (verify, GitHub Release `files:`, Play upload `releaseFiles:`).
- **Never declare a workflow fix done from inspection alone.** Confirm the actual artifact path / behavior before claiming a fix — read the failing run's stdout (`✓ Built …` lines name the real path), or push to a branch and watch CI. If you cannot verify, say so explicitly instead of asserting success.

## Testing conventions

- Import `createTestDatabase()` from `test/shared/test_database.dart` — returns `AppDatabase(NativeDatabase.memory())`. Always `await db.close()` in `tearDown`. (Integration tests have their own copy in `integration_test/shared/test_infrastructure.dart`.)
- Build DB seed rows inline with `Companion.insert(...)` — no DB fixture files. (EPUB/SAF byte fixtures live in `test/shared/`.)
- MeCab needs device assets — cannot run in unit tests. For compound-word tests, construct `WordIdentification` objects directly.
- Integration tests live in `integration_test/` and run on a real emulator via `.github/workflows/integration-android.yml`. Keep them out of `test/`.

## Tools

Prefer Serena MCP tools (`get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, `search_for_pattern`, `replace_symbol_body`) over Read/Grep/Edit for code work — much cheaper in context.
