<p align="center">
  <img src="docs/icon.png" alt="Mekuru" width="96" height="96">
</p>

# Mekuru - Japanese EPUB and Manga Reader

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

Mekuru is a Japanese-first EPUB and manga reader built with Flutter for language learners and native readers. It combines vertical EPUB reading, Mokuro and CBZ manga support, offline dictionaries, and vocabulary tools in one app.

<p align="center">
  <img src="docs/documentation/screenshots/library-screen-imported-books-and-manga.jpg" alt="Library" width="200">
  <img src="docs/documentation/screenshots/epub-reader-navigation-view.jpg" alt="EPUB Reader" width="200">
  <img src="docs/documentation/screenshots/dictionary-lookup-grouped-results.jpg" alt="Dictionary Lookup" width="200">
  <img src="docs/documentation/screenshots/manga-reader-spread-settings.jpg" alt="Manga Reader" width="200">
</p>

**[Homepage](https://mekuru.matthew.moe/)** | **[Documentation](https://mekuru.matthew.moe/documentation/#/)** | **[Google Play](https://play.google.com/store/apps/details?id=moe.matthew.mekuru)**

## Install

<a href="https://play.google.com/store/apps/details?id=moe.matthew.mekuru">
  <img alt="Get it on Google Play" src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" width="200">
</a>

Signed APKs are also available on [GitHub Releases](https://github.com/mostrowski123/japanese-e-reader/releases).

### Beta Testing

To get early access to updates before they reach the public listing:

1. Join [mekuru-testing-group](https://groups.google.com/g/mekuru-testing-group).
2. Open the [Google Play testing page](https://play.google.com/apps/testing/moe.matthew.mekuru).
3. Install or update Mekuru from that page.

## Features

- **EPUB Reader**: Vertical or horizontal reading, RTL or LTR page flow, automatic progress restore, bookmarks, and per-book reader settings
- **Manga Reader**: Mokuro and CBZ support with single-page, spread, and scroll modes
- **Offline Dictionaries**: Import Yomitan ZIPs, Yomitan collection JSON backups, or download built-in packs such as JMdict, KANJIDIC, KanjiVG, and JPDB frequency data
- **Smart Japanese Lookups**: MeCab-powered tokenization, compound-word matching, pitch accents, stroke-order diagrams, and frequency data
- **Vocabulary Workflow**: Save words with sentence context, browse saved terms, export CSV for Anki, or send cards directly to AnkiDroid on Android
- **Reader Customization**: Themes, color modes, margins, swipe sensitivity, and other reader controls
- **Optional Pro Upgrade**: Unlocks book highlights, manga auto-crop, and custom-server OCR support for remote manga OCR

## Pro Features

Mekuru is free and open source. The optional one-time Pro upgrade unlocks:

- Book highlights
- Manga auto-crop
- Custom-server OCR support for remote manga OCR

Remote OCR requires your own OCR endpoint. See the [custom server guide](docs/documentation/manga/custom-server.md) for setup details.

## Roadmap

- Cloud sync for reading progress and vocabulary across devices

## Technology Stack

- **Framework**: [Flutter](https://flutter.dev/) with Dart
- **State Management**: [Riverpod](https://riverpod.dev/) with code generation
- **Database**: [Drift](https://drift.simonbinder.eu/) over SQLite
- **Reader Rendering**: [epub.js](https://github.com/futurepress/epub.js) bridged through [InAppWebView](https://pub.dev/packages/flutter_inappwebview)
- **Japanese Analysis**: [mecab_for_flutter](https://pub.dev/packages/mecab_for_flutter) for tokenization and word boundary detection
- **Backend Services**: Firebase Auth plus optional TypeScript Firebase Functions for OCR-related services

## Getting Started

### Prerequisites

- Flutter stable with Dart SDK 3.10.8 or newer
- Android SDK plus a connected Android device or emulator
- Node.js 22 if you plan to work on the optional `functions/` backend

Android is the primary supported platform today. Some integrations, including Google Play billing and AnkiDroid support, are Android-only.

### Installation

```bash
git clone https://github.com/mostrowski123/japanese-e-reader.git
cd japanese-e-reader

flutter pub get

# Generates Drift, Riverpod, and environment config code
dart run build_runner build --delete-conflicting-outputs

flutter run
```

### Common Development Commands

```bash
flutter analyze
flutter test
dart run build_runner watch --delete-conflicting-outputs
```

### Localization Workflow

Runtime localization uses Flutter's native `gen_l10n` pipeline with ARB files in `lib/l10n/`.

- Source strings live in `lib/l10n/app_en.arb`
- Translated strings live directly in `lib/l10n/app_es.arb`, `lib/l10n/app_id.arb`, and `lib/l10n/app_zh_Hans.arb`
- Generated localizations are produced with `flutter gen-l10n`
- Target locales are currently `es`, `id`, and Simplified Chinese (`zh_Hans`)
- Flutter also keeps a matching `app_zh.arb` base fallback because script-code locales require a base `zh` ARB
- Update translations directly in the ARB files, either manually or with the coding agent
- Regenerate Flutter localization output with `flutter gen-l10n`
- Check for untranslated messages in `build/untranslated_messages.json`
- Run `flutter analyze` and `flutter test`
- If a translation is wrong or awkward, contributors should open an issue or send a pull request against the ARB files

See [docs/translation-workflow.md](docs/translation-workflow.md) for the repo-specific translation workflow.

### Optional Firebase Functions Workflow

```bash
cd functions
npm ci
npm run build
```

To deploy the backend and Firestore rules:

```bash
firebase deploy --only functions,firestore:rules
```

## Project Structure

```text
lib/
|-- app.dart
|-- main.dart
|-- config/
|-- core/
|-- features/
|   |-- ankidroid/
|   |-- backup/
|   |-- dictionary/
|   |-- library/
|   |-- manga/
|   |-- reader/
|   |-- settings/
|   `-- vocabulary/
`-- shared/

functions/   # Optional TypeScript Firebase Functions
docs/        # Documentation site content
```

Feature modules follow a `data/` and `presentation/` split for models, repositories, services, providers, screens, and widgets.

## Contributing

Contributions are welcome. Before opening a pull request:

1. Fork the repository.
2. Create a branch for your change.
3. Run `flutter analyze` and `flutter test`.
4. Include any required code generation updates, including `flutter gen-l10n` when localization files change.

See [CLAUDE.md](CLAUDE.md) for additional codebase conventions and architecture notes.

## License

This project is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE) for details.
