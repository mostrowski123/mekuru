# Translation Workflow

Mekuru uses Flutter's native ARB-based localization pipeline.

## Source Of Truth

- English source strings live in `lib/l10n/app_en.arb`
- Generated Dart localization files live in `lib/l10n/generated/`
- Lingo.dev repository configuration lives in `i18n.json`
- `lib/l10n/app_zh.arb` mirrors `lib/l10n/app_zh_Hans.arb` as Flutter's required base fallback for Simplified Chinese

## Adding Or Updating Translations

1. Add or update English strings in `lib/l10n/app_en.arb`
2. Run `npx lingo.dev@latest run --no-interactive`
3. Copy `lib/l10n/app_zh_Hans.arb` to `lib/l10n/app_zh.arb` and change `@@locale` in the copy to `zh`
4. Run `npx lingo.dev@latest lockfile --no-interactive`
5. Run `flutter gen-l10n`
6. Commit the ARB changes, `i18n.lock`, and regenerated localization output together

## Adding A New Locale

1. Add the locale code to `i18n.json`
2. Run `npx lingo.dev@latest run --no-interactive`
3. For Flutter script-code locales, prefer Flutter-compatible locale codes such as `zh_Hans`
4. If you add `zh_Hans`, also keep `app_zh.arb` in sync as the base fallback file
5. Run `npx lingo.dev@latest lockfile --no-interactive`
6. Run `flutter gen-l10n`

`MaterialApp.supportedLocales` is generated from committed ARB files, so new locales become available at runtime once their ARB files are present.

## Human Review

AI-generated translations are expected to be the starting point, not the final authority.

- Open an issue if you notice a bad translation
- Send a pull request against the ARB files to fix wording
- Keep translation fixes in source control so they are reviewable and reproducible
