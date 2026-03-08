# Translation Workflow

Mekuru uses Flutter's native ARB-based localization pipeline.

## Source Of Truth

- English source strings live in `lib/l10n/app_en.arb`
- Translated strings live alongside them in `lib/l10n/app_es.arb`, `lib/l10n/app_id.arb`, and `lib/l10n/app_zh_Hans.arb`
- Generated Dart localization files live in `lib/l10n/generated/`
- `lib/l10n/app_zh.arb` mirrors `lib/l10n/app_zh_Hans.arb` as Flutter's required base fallback for Simplified Chinese

## Adding Or Updating Translations

1. Add or update English strings in `lib/l10n/app_en.arb`
2. Update the translated ARB files directly in git, either manually or with the coding agent
3. Copy `lib/l10n/app_zh_Hans.arb` to `lib/l10n/app_zh.arb` and change `@@locale` in the copy to `zh`
4. Run `flutter gen-l10n`
5. Run `flutter analyze`
6. Run `flutter test`
7. Commit the ARB changes and regenerated localization output together

## Adding A New Locale

1. Add a new `app_<locale>.arb` file under `lib/l10n/`
2. Add the locale to any app-level locale pickers or tests if needed
3. For Flutter script-code locales, prefer Flutter-compatible locale codes such as `zh_Hans`
4. If you add `zh_Hans`, also keep `app_zh.arb` in sync as the base fallback file
5. Run `flutter gen-l10n`
6. Run `flutter analyze`
7. Run `flutter test`

`MaterialApp.supportedLocales` is generated from committed ARB files, so new locales become available at runtime once their ARB files are present.

## Validation

- `l10n.yaml` writes untranslated keys to `build/untranslated_messages.json`
- Keep ARB resource attributes up to date so placeholders and descriptions stay accurate
- Review translation changes in git like any other source change

## Optional Editing Helpers

No extra translation platform is required for this repo.

- `i18n Ally` can make key lookup and ARB editing easier inside the editor
- Desktop editors such as BabelEdit or Lyrebird are optional convenience tools if you want a visual ARB editor later
