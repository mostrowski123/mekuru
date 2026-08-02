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
- **State**: Riverpod with codegen. The global `databaseProvider` is created once in `lib/main.dart` — **never instantiate `AppDatabase` elsewhere**, including in tests (use `createTestDatabase()` instead).
- **Pure-logic files** (e.g. `reader_interaction_logic.dart`, `compound_word_resolver.dart`) must stay Flutter-free so they remain unit-testable.

## Database — Drift, append-only migrations

Schema is at version 19, defined inline in `lib/core/database/database_provider.dart`. Migrations live in the `MigrationStrategy.onUpgrade` block as cumulative `if (from < N) { … }` conditions.

**YOU MUST** make schema changes append-only: add columns/tables, never drop or rename them on an existing version. Bump `schemaVersion` and add a new `if (from < N)` block. Reckless edits break installed users' data — there is no rollback.

In-memory test databases skip migrations entirely (they start at the latest schema). Schema-compat issues won't surface in unit tests; rely on integration tests.

## Japanese text pipeline

- **MeCab**: singleton at `MecabService.instance`, initialized in `main.dart`. IPADIC is bundled at `assets/ipadic/` and copied to `applicationDocumentsDirectory` on first launch. UniDic-lite is optionally **downloaded** by the user; `init()` silently falls back to IPADIC if UniDic init fails.
- **Compound words**: greedy longest-match up to 5 tokens (`maxTokenSpan = 5`) against the *enabled* dictionary set.
- **Dictionary queries**: always join `DictionaryMetas` and filter by `isEnabled`. Disabled dictionaries must never surface results.
- **Glossaries**: stored as raw JSON strings in Drift — no type converters. Parse on read.

## Reader / EPUB viewer

- `assets/epub_viewer/reader_bridge.js` — hand-written bridge that talks to Dart via `window.flutter_inappwebview.callHandler(...)`. Owns vertical text, margins, furigana injection, word tapping.
- `assets/epub_viewer/epub.js` — **vendored** epub.js, locally modified. Before editing it, search for `[MEKURU PATCH]` — those markers flag every place upstream behavior is overridden (vertical-axis forcing, queue error handling, missing-manifest-entry skipping, etc.). Don't re-vendor without porting the patches.
- Don't change the bridge's message protocol without updating the matching Dart handlers in the reader feature.

## Android / native

- **`libc++_shared.so` workaround**: `mecab_for_flutter`'s native_assets hook fails on GitHub-hosted runners, so we bundle the lib manually via a `jniLibs` source set in `android/app/build.gradle.kts` (search `bundledLibCppSharedJniLibsDir`). **Do not remove** without verifying CI Android builds still link.
- **Firebase**: `lib/firebase_options.dart` is committed. `android/app/google-services.json` is required for local Android builds and is in the repo.
- **OCR billing / Pro**: validated server-side by the `billingApiV2` Cloud Function. Never bypass token validation or treat the client-side `proAccessProvider` as ground truth — round-trip the server.
- **AnkiDroid integration** is Android-intent-based; do not call from non-Android code paths.

## CI / release workflows

`.github/workflows/build-release.yml` produces the Play artifact. Two gotchas have bitten this workflow repeatedly:

- **AAB output path includes the flavor.** With `--flavor X`, AGP writes the bundle to `build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab` — e.g. `bundle/playRelease/app-play-release.aab`. APKs are flat (`flutter-apk/app-<flavor>-release.apk`), but bundles are not. Any time you change the flavor flag, update every `bundle/...` path in the workflow (verify, GitHub Release `files:`, Play upload `releaseFiles:`).
- **Never declare a workflow fix done from inspection alone.** Confirm the actual artifact path / behavior before claiming a fix — read the failing run's stdout (`✓ Built …` lines name the real path), or push to a branch and watch CI. If you cannot verify, say so explicitly instead of asserting success.

## Testing conventions

- Use the `createTestDatabase()` helper — returns `AppDatabase(NativeDatabase.memory())`. Always `await db.close()` in `tearDown`.
- Build seed rows inline with `Companion.insert(...)`. No fixture files.
- MeCab needs device assets — cannot run in unit tests. For compound-word tests, construct `WordIdentification` objects directly.
- Integration tests live in `integration_test/` and run on a real emulator via `.github/workflows/integration-android.yml`. Keep them out of `test/`.

## Tools

Prefer Serena MCP tools (`get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, `search_for_pattern`, `replace_symbol_body`) over Read/Grep/Edit for code work — much cheaper in context.
