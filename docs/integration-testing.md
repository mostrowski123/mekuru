# Integration Testing

Emulator-based integration tests live in `integration_test/` and run in CI via the
**Android Integration Tests** workflow (`.github/workflows/integration-android.yml`).

## What Runs in CI

The workflow boots a real Android emulator (API 34 `google_atd` x86_64, `pixel_6`
profile, cached AVD) and runs these 18 test files in a single invocation:

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
- `furigana_generator_flow_test.dart` — real MeCab tokenization → furigana
- `manga_word_segmentation_test.dart` — real MeCab, one parse per mokuro line
- `reader_indesign_vertical_epub_test.dart` — real WebView, vertical pagination

Shared plumbing: `integration_test/test_helpers.dart`,
`integration_test/shared/test_infrastructure.dart`,
`integration_test/shared/word_tap_scenario.dart`, and the driver entry point
`test_driver/integration_test.dart`.

## Not Run in CI

These files exist but are deliberately **not** in the CI script. Run them locally
(emulator, never a personal device) when touching those areas:

- `reader_resume_reopen_test.dart` — fails on the CI image (Aug 2026, run
  31293734539): `tester.pageBack()` finds no `CupertinoNavigationBarBackButton`
  after the second reader open, and the failed WebView test then hangs teardown
  until the step's 30-minute timeout kills the whole run — so a failure costs
  the full budget, not one red test. Passes on local emulators.
- `dictionary_scroll_benchmark_test.dart` — informational only: no pass/fail
  thresholds, it just prints frame timings, which are meaningless noise on a
  shared CI runner.
- `word_tap_lookup_test.dart` (+ `_vertical`, `_furigana_on`, `_furigana_book`,
  `_furigana_above_level` variants) — synthetic-tap delivery into InAppWebView is
  emulator-sensitive (see the header of `shared/word_tap_scenario.dart`: only the
  first WebView instance per process reliably receives taps, so each scenario is
  its own file; behavior verified on API 36, unverified on CI's API 34
  `google_atd`). Five extra per-file app launches would also eat most of the
  remaining 30-minute test-step budget (the 18-file suite already takes ~25 min,
  measured Aug 2026, run 31295011131).

Except for `reader_resume_reopen_test.dart` (tried and reverted in Aug 2026,
see above), none of these were ever removed from CI — the script has only ever
grown; they were simply never added.

## Local Commands

Use an Android emulator (never a personal device), then run a single file:

```bash
flutter test integration_test/app_smoke_test.dart \
  -d emulator-5554 \
  --dart-define=FORCE_DEBUG_APP_CHECK_PROVIDER=true \
  -r expanded
```

To reproduce the full CI suite, pass the same 18 files listed above to one
`flutter test` invocation with the same flags (see the `script:` line in
`integration-android.yml` for the exact command).

## CI Triggers

- **Pull requests**: runs when app code or integration-test files change (path-filtered)
- **`main`**: runs on push
- **Manual**: `workflow_dispatch`

There is no scheduled/nightly run. Job timeout is 45 minutes (30 for the test step);
the AVD is cached between runs (`avd-34-google_atd-x86_64-v1`).
