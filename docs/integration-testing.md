# Integration Testing

This repo now has a dedicated Android emulator smoke test in
`.github/workflows/integration-android.yml`.

## What Runs Today

- Boot the real app on an Android emulator
- Wait for startup to finish and verify the bottom navigation renders
- Navigate to Dictionary, Vocabulary, and Settings
- Assert each tab reaches a stable empty-state screen

The implemented test lives in `integration_test/app_smoke_test.dart`.

## Local Command

Use an Android emulator or connected device, then run:

```bash
flutter test integration_test/app_smoke_test.dart \
  -d emulator-5554 \
  --dart-define=FORCE_DEBUG_APP_CHECK_PROVIDER=true \
  -r expanded
```

## Next Scenarios To Add

1. EPUB import -> open reader -> move forward -> relaunch -> progress restored
2. Backup export -> clear app data -> restore -> saved words/bookmarks/highlights restored
3. Starter pack install with fake download services -> dictionary search works end to end
4. Manga import fixture -> reader opens -> word overlay opens lookup sheet
5. Reader settings change -> reopen the same book -> per-book settings persist

## CI Schedule

- Pull requests: smoke test runs when app or integration-test files change
- `main`: smoke test runs on pushes
- Nightly: scheduled for 03:17 JST every day

GitHub Actions schedules run in UTC and can be delayed during high-load periods,
so the nightly job intentionally avoids the top of the hour.
