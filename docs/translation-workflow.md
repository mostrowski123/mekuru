# Translation Workflow

Mekuru uses Flutter's native ARB-based localization pipeline.

## Source Of Truth

- English source strings live in `lib/l10n/app_en.arb`
- Generated Dart localization files live in `lib/l10n/generated/`
- Lingo.dev repository configuration lives in `i18n.json`

## Adding Or Updating Translations

1. Add or update English strings in `lib/l10n/app_en.arb`
2. Run `flutter gen-l10n`
3. Use your Lingo.dev workflow, including MCP if desired, to generate or update `app_<locale>.arb` files
4. Commit the ARB changes and regenerated localization output together

## Adding A New Locale

1. Create `lib/l10n/app_<locale>.arb`
2. Add the locale code to `i18n.json`
3. Run `flutter gen-l10n`

`MaterialApp.supportedLocales` is generated from committed ARB files, so new locales become available at runtime once their ARB files are present.

## Human Review

AI-generated translations are expected to be the starting point, not the final authority.

- Open an issue if you notice a bad translation
- Send a pull request against the ARB files to fix wording
- Keep translation fixes in source control so they are reviewable and reproducible
