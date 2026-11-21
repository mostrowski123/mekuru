# Rules and what enforces them

Each rule in `CLAUDE.md`, and what fails when it is broken. "nothing" marks where the next check belongs.
`rule_table_test.dart` in this folder checks that every file named here exists.

| Rule | Fails when broken |
|---|---|
| iOS work leaves Android unchanged | partly: unit tests, which run as Android, and `integration-android.yml` |
| iOS is not left behind | nothing |
| An Android-only feature gets an iOS equivalent or is hidden on iOS | partly: some screen tests under the iOS override |
| `defaultTargetPlatform`, not `Platform.isIOS` | `test/architecture/raw_api_test.dart` |
| A new stored absolute path is re-anchored at boot | partly: `test/features/backup/prepare_staged_restore_test.dart` (existing columns) |
| Copy that names Android things gets an `…Ios` key | nothing |
| Every `app_en.arb` key is in every `app_*.arb` | `scripts/check_release_ready.py` in `build-release.yml`, `release-ios.yml`, `build-pr.yml` |
| Reader JavaScript works in WKWebView and Chromium | partly: reader tests in `integration-android.yml` and `integration-ios.yml` |
| A new plugin supports iOS 26 | partly: `build-ios-pr.yml` |
| A new plugin's `Info.plist` string and required-reason APIs | nothing |
| iOS builds after `ios/`, plugin or native asset changes | `build-ios-pr.yml`, `integration-ios.yml` |
| One iOS build at a time per checkout | nothing |
| `pod install` after changing `ios/Podfile` | nothing |
| Integration tests run through `scripts/run_integration_tests.sh` | partly: CI does, a local bare flutter test does not |
| Codegen after editing `@DriftDatabase` or `environment_config.yaml` | partly: the compiler, for a missing generated member |
| `dart format` only the files you changed | nothing |
| `flutter analyze lib test integration_test benchmark` is clean, infos too | `checks.yml` "Run static analysis" |
| `flutter test` passes | `checks.yml` "Run tests" |
| Bump `version:` for user-facing changes: minor for feat, patch for fix, iOS-only too | partly: `scripts/check_release_ready.py` in `build-release.yml` (any bump, Android pushes only) |
| No `Co-Authored-By:` trailer | nothing |
| Conventional commit prefix; feat, fix, perf and l10n subjects written for users | nothing |
| Feature-first layout | nothing |
| `AppDatabase` built only in `lib/main.dart` | nothing |
| Tests use `createTestDatabase()` | nothing |
| Pure-logic files import no Flutter above `foundation.dart` | nothing |
| No personal data in telemetry; book titles in breadcrumbs only | partly: `test/core/usage_telemetry_test.dart` (paths in error text) |
| Append-only schema, a `schemaVersion` bump, an `if (from < N)` block | partly: `test/database_migration_test.dart` |
| Late columns also re-added by `_repairMissingColumns` | partly: `test/database_migration_test.dart` |
| `applyStagedFullRestoreIfAny()` first in `_bootApp`, `IosFullBackup.start()` after it | nothing |
| Staging with neither marker is never applied | `test/features/backup/staged_full_restore_test.dart` |
| Retire a directory to a tombstone before deleting it | partly: `test/features/backup/staged_full_restore_test.dart` |
| Cascade deletes in repository code | partly: deletion tests such as `test/collection_repository_test.dart` |
| MeCab only through `MecabService.instance` | `lib/features/reader/data/services/mecab_service.dart` (private constructor) |
| MeCab starts on IPADIC and stays there if UniDic-lite fails | partly: `integration_test/mecab_enhanced_dict_upgrade_test.dart` (not the failure) |
| Compound words: longest match, at most 5 tokens, enabled dictionaries | `test/compound_word_resolver_test.dart` |
| Queries skip disabled dictionaries | partly: `test/dictionary_query_service_test.dart` |
| Glossaries stay raw JSON, with no type converter | nothing |
| Both FTS creation paths build the same triggers | partly: `test/dictionary_glossary_fts_test.dart` (names and inserts) |
| Styles start from `japaneseTextStyle` | partly: `test/shared/japanese_text_locale_test.dart` (per file, not per call) |
| A section with no language gets the book's, else `ja` | `integration_test/reader_bridge_regression_test.dart` |
| Writers of `glossaries` refresh `searchText` | nothing |
| Search `[MEKURU PATCH]` before editing `epub.js`; port every patch on a re-vendor | nothing |
| Bridge protocol and Dart handlers change together | partly: `tool/bridge_test/run.mjs` (names, not arguments) |
| Bridge test after changing `reader_bridge.js` or `epub.js` | `bridge-test.yml` |
| MeCab libs and `libc++_shared.so` in every Android artifact | `scripts/verify_native_libs.py` in `build-pr.yml` and `build-release.yml` |
| `ocr.play_entitlement` cleared only by a successful query without the SKU | `test/features/manga/data/services/ocr_store_service_test.dart` |
| No `billingApiV2` bypass; no consumable acknowledged without the grant | partly: `test/features/manga/data/services/ocr_store_service_test.dart` |
| AnkiDroid only on Android; iOS behind `AnkidroidService` | nothing |
| Every WorkManager job through `ocrWorkerCallbackDispatcher`, never renamed or moved | nothing |
| Runtime permissions through `FullBackupJobBridge` | nothing |
| Keep rules for JNI-built classes; OCR changes tested on `--release` | nothing |
| `fileImage()`, not `Image.file` | `test/architecture/raw_api_test.dart` |
| `avif_manga_test.dart` on Android 11 or older and iOS after AVIF changes | nothing |
| OCR scans never in a foreground service | nothing |
| OCR model manifest only from `tools/prepare_ocr_manifest.py` | partly: `test/features/manga/data/services/ocr_distribution_test.dart` |
| NDL: PARSeq only, never DEIM | partly: `test/features/manga/data/services/ndl_ocr_algorithms_test.dart` |
| `NdlAlgorithms.kt` and `ndl_ocr_algorithms.dart` change together | partly: `test/features/manga/data/services/ndl_ocr_algorithms_test.dart`, the Kotlin side in `build-pr.yml` only |
| Native code in `AppDelegate.swift`, logic in Dart | nothing |
| iOS never exits by itself; a restore applies through `restartAppInProcess()` | nothing |
| Boot steps safe to run twice; library writers stop when a restore starts | nothing |
| No GPL detector code ported to iOS | nothing |
| No `comictextdetector.onnx` download on iOS | `test/features/manga/data/services/manga_ocr_algorithms_test.dart` |
| `manga_ocr_algorithms.dart` and `OcrAlgorithms.kt` change together | partly: `test/features/manga/data/services/manga_ocr_algorithms_test.dart`, the Kotlin side in `build-pr.yml` only |
| Manga109-s data stays in the gitignored `example/` | partly: `test/features/manga/data/services/ocr_distribution_test.dart` (plugin assets) |
| A transaction with `revocationDate` is not owned | `test/features/manga/data/services/ocr_store_service_test.dart` |
| iOS ownership from `SK2Transaction.transactions()`, not `restorePurchases()` | partly: `test/features/manga/data/services/ocr_store_service_test.dart` |
| iOS workflows on `xcode-27` | nothing |
| Pushed screens through `namedRoute`; full-bleed ones in `_fullBleedRoutes` | partly: `test/shared/app_routes_test.dart` (the first half) |
| The Flutter pin moves with its migration, in all seven workflows at once | nothing |
| No ad-ID Analytics frameworks in `Runner.app` | "Verify native frameworks" in `build-ios-pr.yml` and `release-ios.yml` |
| No `--build-name`, no Runner `MARKETING_VERSION` | nothing |
| `version:` moves on after an App Store approval | partly: `release-ios.yml`, at the TestFlight upload |
| The App Store Connect version record matches the build | nothing |
| Submit or release only when Matt asks; never set the declarations | nothing |
| A flavor change updates every `bundle/...` path | partly: `build-release.yml` verify step, after the push |
| A workflow fix is confirmed from a run | nothing |
| `await db.close()` in `tearDown` | nothing |
| Seed rows with `Companion.insert(...)`, no DB fixture files | nothing |
| No MeCab in unit tests | nothing: an uninitialized MeCab returns no tokens |
| Integration tests run in a workflow | partly: `test/architecture/ci_coverage_test.dart` (or its exclusion table) |
| Integration tests stay out of `test/` | nothing |
| Serena symbol tools for code | nothing |
