# Mekuru (めくる)

Japanese-first EPUB and manga reader. Flutter, **Android and iOS** (iOS 18+; `firebase_options.dart` throws on web/desktop). Android is the shipped platform: every iOS change must leave Android behaviour identical, so add an iOS branch rather than editing the Android path.

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
flutter build ios --no-codesign                            # iOS release build (what CI checks)
scripts/run_ios_integration_tests.sh <simulator-udid> integration_test/x_test.dart   # iOS, one file at a time
```

iOS: never run two iOS builds at once in this checkout (an integration-test run counts; they share `build/ios` and the loser fails to link). After changing `ios/Podfile`, run `pod install` in `ios/` with `LANG=en_US.UTF-8`. A failing integration test can hang on a simulator instead of failing, hence the script's per-file watchdog.

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

**Full backup/restore is a native job; full restore swaps the database file at boot.** The archive is written and unpacked by the Kotlin foreground service (`FullBackupJobService`, pure-JVM core under `android/.../backup/`) from `<appSupport>/full_backup_job/` (`job.json`, `plan.jsonl`, `journal.jsonl`, `CANCELLED`, `result.json`); the Dart side only prepares and observes it. A restore ends with `restore_staging/EXTRACTED`; `applyStagedFullRestoreIfAny()` (`lib/features/backup/data/services/staged_full_restore.dart`) must stay the first statement in `main`'s app runner: it runs the fix-ups (`prepareStagedRestore` → `READY`; this is also where a manga linked from an outside folder becomes an ordinary one reading from `<dir>/pages/`), then renames `restore_staging/mekuru_db.sqlite` and `restore_staging/books/` into place (and `restore_staging/unidic-lite/` into the app **documents** dir, when the archive had it), and nothing may open the database, touch `books/` or load MeCab before it. A staging dir with neither marker belongs to the job (or to a cancel in progress) and is never applied. `restore_staging/`, `restore_rollback/`, `full_backup_job/` and `*.trash` tombstones under app support belong to this machinery; never delete a directory there in place, retire it to a tombstone first (`StagedFullRestore.retire` / `JobStore.retire`).

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
- **OCR billing / Pro**: the Pro unlock's ground truth is Google Play ownership of `pro_unlock_v1`, recorded client-side in the secure-storage key `ocr.play_entitlement` (purchase/restore need no Google sign-in). That key is cleared ONLY by a successful Play owned-purchases query that omits the SKU — never on errors; for signed-out buyers that query is the only refund-revocation channel (the backend RTDN handler no-ops on tokens it never saw). The `billingApiV2` Cloud Function remains ground truth for cloud OCR and credits (dormant) — never bypass its token validation, and never acknowledge a credit consumable without the server grant.
- **AnkiDroid integration** is Android-intent-based; do not call from non-Android code paths.
- **Runtime permissions**: never request one from a Flutter plugin. `ankidroid_for_flutter` force-unwraps its pending result on every `onRequestPermissionsResult`, so any foreign permission callback crashes the app. Request through `FullBackupJobBridge` (its request code is answered in `MainActivity.onRequestPermissionsResult` before `super` fans the result out to plugins); on-device OCR's notification prompt goes this way.
- **Release builds are R8-minified** (Flutter's Gradle plugin enables shrinking for `--release`). Any library whose Java classes are constructed from JNI needs consumer keep rules or release crashes where debug works: `packages/local_manga_ocr/android/consumer-rules.pro` keeps `ai.onnxruntime.**` and `org.opencv.**` for exactly that reason (release-only SIGABRT in `OrtSession.getInputInfo`, 2026-09-11). Test OCR changes on a `--release` build before shipping a preview.
- **On-device OCR** lives in `packages/local_manga_ocr` (Kotlin + JNI + OpenCV DNN detector + onnxruntime recognizer, manga-ocr-base weights downloaded at runtime). JVM tests: `.ndroid\gradlew.bat -p android :local_manga_ocr:testDebugUnitTest` from PowerShell. Regenerate the model manifest only with `tools/prepare_ocr_manifest.py`. See Serena memory `local_ocr_architecture` for the service/journal invariants.

## iOS / native

- **Project**: scheme and configurations `play` (`Debug-play` etc.; there is no `parallel` flavor on iOS). Plugins come through Swift Package Manager; CocoaPods remains for `flutter_inappwebview_ios`, `workmanager_apple` and `onnxruntime-objc`. Deployment target 18.0 (policy: the last three major iOS versions).
- **All app-level native code is in `ios/Runner/AppDelegate.swift`**, as method channels: `mekuru/ios_storage` (exclude re-downloadable data from backups), `mekuru/vision_ocr` (Apple Vision text lines, and `MangaOcrModel`, a thin ONNX Runtime wrapper), `mekuru/ios_files` (`FilesBridge`: move a file out through the document picker, pick a zip, free space). Logic stays in Dart where it is unit-testable; Swift stays thin.
- **Nothing runs in the background on iOS.** OCR scans and full-backup jobs run inside the app with the wakelock held (`determineOcrTaskExecutionMode` is always foreground on iOS; `DartFullBackupJob` replaces the Android service). Work that dies with the app is restarted by the user: `resetInterruptedIosOcr()` and `DartFullBackupJob.recover()` clean up at launch. `IosFullBackup.start()` must stay after `applyStagedFullRestoreIfAny()` in `main`.
- **On-device OCR on iOS contains no GPL code.** Text is found with Apple Vision through the Swift `RecognizeTextRequest` (the older `VNRecognizeTextRequest` barely sees vertical Japanese), grouped into blocks by `vision_block_grouping.dart`, and read by manga-ocr per block when the optional model pack is installed (`manga_ocr_ios.dart`; Vision's own text otherwise). **Never translate or paraphrase `ComicGeometry.kt` or the detector parts of `MangaOcrEngine.kt`** (ported from GPL comic-text-detector), and never download `comictextdetector.onnx` on iOS. `manga_ocr_algorithms.dart` mirrors the app's own `OcrAlgorithms.kt` and shares its test vectors; change both together. Benchmarks: `tools/manga109_ocr_benchmark.py` (data stays under the gitignored `example/`; Manga109-s may not be redistributed).
- **Pro on iOS** is a separate StoreKit purchase of `pro_unlock_v1`, same secure-storage key and clearing rule as Android. The StoreKit plugin reports a refund notice as `purchased`: a transaction only counts as owned when its JSON has no `revocationDate` (`isOwnedAppStorePurchase`), and ownership comes from `SK2Transaction.transactions()`, not `restorePurchases()` (its reply races its events). No server verification on iOS yet.
- **Anki on iOS**: `AnkiMobileService` (URL scheme, add-only, names typed by the user) or `AnkiConnectService` (HTTP to Anki on a computer), both behind the `AnkidroidService` contract.

## CI / release workflows

iOS: `build-ios-pr.yml` (release build without signing, plus a check that the MeCab and sqlite frameworks are in `Runner.app`), `integration-ios.yml` (simulator tests through `scripts/run_ios_integration_tests.sh`), `release-ios.yml` (TestFlight: unsigned archive, then every framework and the app are ad-hoc signed with `Runner.entitlements` before `xcodebuild -exportArchive` signs with a cloud-managed certificate, because the export step re-signs only fully signed code and reads entitlements from the signature; the App Store Connect API key needs the Admin role).

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
