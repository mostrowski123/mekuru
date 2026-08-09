# Integration Testing

Emulator-based integration tests live in `integration_test/` and run in CI via the
**Android Integration Tests** workflow (`.github/workflows/integration-android.yml`).

## What Runs in CI

The workflow boots a real Android emulator (API 34 `google_atd` x86_64, `pixel_6`
profile, cached AVD) and runs these 15 test files in a single invocation:

- `app_smoke_test.dart` — startup, bottom nav (Library / Dictionary / Vocabulary / You), Settings via the You-tab gear
- `dictionary_search_flow_test.dart`
- `vocabulary_lifecycle_test.dart`
- `settings_persistence_test.dart`
- `cross_feature_navigation_test.dart`
- `backup_restore_roundtrip_test.dart`
- `bookmark_highlight_persistence_test.dart`
- `pending_restore_flow_test.dart`
- `reader_progress_persistence_flow_test.dart`
- `dictionary_import_flow_test.dart`
- `vocabulary_csv_export_test.dart`
- `library_import_flow_test.dart`
- `collections_flow_test.dart`
- `mecab_enhanced_dict_upgrade_test.dart`
- `epub_furigana_export_flow_test.dart`

Shared plumbing: `integration_test/test_helpers.dart`,
`integration_test/shared/test_infrastructure.dart`,
`integration_test/shared/word_tap_scenario.dart`, and the driver entry point
`test_driver/integration_test.dart`.

## Not Run in CI

These files exist but are **not** in the CI script (word-tap/segmentation scenarios
need bundled MeCab assets and are slower; the benchmark is informational). Run them
locally when touching those areas:

- `dictionary_scroll_benchmark_test.dart`
- `furigana_generator_flow_test.dart`
- `manga_word_segmentation_test.dart`
- `reader_indesign_vertical_epub_test.dart`
- `reader_resume_reopen_test.dart`
- `word_tap_lookup_test.dart` (+ `_vertical`, `_furigana_on`, `_furigana_book`, `_furigana_above_level` variants)

## Local Commands

Use an Android emulator (never a personal device), then run a single file:

```bash
flutter test integration_test/app_smoke_test.dart \
  -d emulator-5554 \
  --dart-define=FORCE_DEBUG_APP_CHECK_PROVIDER=true \
  -r expanded
```

To reproduce the full CI suite, pass the same 15 files listed above to one
`flutter test` invocation with the same flags (see the `script:` line in
`integration-android.yml` for the exact command).

## CI Triggers

- **Pull requests**: runs when app code or integration-test files change (path-filtered)
- **`main`**: runs on push
- **Manual**: `workflow_dispatch`

There is no scheduled/nightly run. Job timeout is 45 minutes (30 for the test step);
the AVD is cached between runs (`avd-34-google_atd-x86_64-v1`).
