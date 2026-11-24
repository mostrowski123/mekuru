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
| Copy that names Android things gets an `…Ios` key | partly: `test/architecture/raw_api_test.dart` fails on a raw platform check that picks such a key; nothing checks that the key exists |
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
| Tests use `createTestDatabase()` | `test/architecture/raw_api_test.dart` |
| Pure-logic files import no Flutter above `foundation.dart` | nothing |
| No personal data in telemetry; book titles in breadcrumbs only | partly: `test/core/usage_telemetry_test.dart` (paths in error text; a file error's path, a platform error's message and a socket error's host never sent), `test/server_settings_screen_test.dart` (a Komga or Kavita server's address) |
| Firebase Analytics reports only from release-workflow builds on real devices | `test/architecture/analytics_gate_test.dart` |
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
| ONNX Runtime on iOS: the pinned NuGet package and the vendored wrapper, changed together | partly: CocoaPods refuses a download whose SHA-256 is not the pin in `ios/podspecs/onnxruntime-c.podspec.json`; nothing checks the vendored sources against `ios/Vendor/onnxruntime-objc/README.md` |
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
| A system file dialog is opened only in `lib/core/platform/file_pick.dart` | `test/architecture/raw_api_test.dart` |
| A save passes a file's path, never its bytes | `test/architecture/raw_api_test.dart` (no other file can reach a save dialog), `test/core/platform/file_pick_test.dart` |
| A download goes through `runDownload` with a `NetworkConsent` | partly: `test/architecture/raw_api_test.dart` (raw HTTP clients and mobile-data consent are counted), `test/shared/downloads/download_kinds_test.dart` |
| A provider's state holds what happened, never user-facing text | `test/architecture/raw_api_test.dart` (a String error or message field in a provider file) |
| An exception's own text never reaches the user | partly: `test/architecture/raw_api_test.dart` for a message in `lib/l10n/app_en.arb` with a placeholder named details or error (two allowed by name, for the OCR server's own explanation), and in Dart for an error passed as details: '$e' or e.toString(), shown with Text('$error') or Text(e.toString()), or returned with => e.toString() or return e.toString(); screen tests in Japanese for downloads, deletes, imports, lists, server errors and the full backup; nothing for other shapes |
| Long work and platform wording are read from `lib/core/platform/capabilities.dart` | partly: `test/core/platform/capabilities_test.dart`; a new inline platform check is caught only when it picks an Ios key |
| A library write from the UI is awaited and its failure shown | partly: `test/features/library/presentation/library_write_failure_test.dart` (existing actions) |
| An EPUB href is decoded with `decodeHref` | `test/architecture/raw_api_test.dart` |
| The reader scripts are checked in a browser | `tool/bridge_test/run.mjs` in `bridge-test.yml` |
| The EPUB viewer is replaced only through `ViewerSession.beginReplacement` | partly: `test/features/reader/presentation/viewer_session_test.dart` |
| An EPUB page turns at once, with no setting; a manga page slides only while Animations is on | `test/features/reader/presentation/reader_screen_page_turn_test.dart`, `test/features/manga/presentation/screens/manga_reader_page_turn_test.dart` |
| Reader input, the seek bar and statistics read the layout on screen, not the settings | partly: `test/features/reader/presentation/reader_screen_shown_layout_test.dart` (existing inputs) |
| A download row is a `DownloadTile` over a `DownloadTileNotifier` | partly: `test/features/settings/download_tiles_test.dart` (the five rows that are); nothing stops a new hand-built row |
| A worker's recorded failure is read by `RecordedDownloadFailure.parse` and worded without a default | the compiler (two switches with no default), `test/download_status_test.dart` (the strings on disk keep their meaning) |
| A folder a download installs is filled beside the old one with `fillInstallFolder` | partly: `test/core/utils/install_folder_test.dart`, `test/features/settings/data/services/kanjivg_download_flow_test.dart`, `test/features/settings/data/services/unidic_download_flow_test.dart` (the two that do) |
| A manga's page data is read through `MangaCacheStore` | partly: `test/features/manga/data/services/manga_cache_store_test.dart`, `test/features/library/manga_pages_missing_test.dart`; nothing stops a second reader |
