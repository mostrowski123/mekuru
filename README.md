# Mekuru — Japanese EPUB Reader

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

A Japanese-first EPUB reader built with Flutter. Designed for language learners studying Japanese, featuring vertical text rendering, offline Yomitan dictionary lookups, MeCab word boundary detection, and vocabulary management with Anki-compatible CSV export.

## Features

- **Library Management**: Import EPUB files, automatically extract metadata and cover images, manage your book collection
- **Vertical Text Rendering**: Native `writing-mode: vertical-rl` via epub.js for authentic Japanese reading
- **RTL Page Navigation**: Right-to-left page turning with tap and swipe gesture support
- **Reading Progress**: Automatically saves your position (CFI-based) and resumes where you left off
- **Chapter Navigation**: Table of contents drawer for jumping between chapters
- **Customizable Display**: Adjustable font size, toggle between vertical and horizontal text modes
- **Manga Reader**: Dedicated manga viewer with spread detection, auto-crop, and scroll/page view modes
- **Manga OCR** *(Pro)*: Cloud-based OCR for extracting text from manga pages for dictionary lookup
- **Offline Dictionary**: Import Yomitan/Yomichan dictionary ZIP files for offline lookups
- **MeCab Word Detection**: Accurate Japanese word boundary detection using morphological analysis
- **Compound Word Resolution**: Multi-token greedy matching against the dictionary for compound words
- **One-Tap Word Save**: Save words directly from dictionary lookups with automatic sentence context capture
- **Vocabulary List**: Browse saved words with readings and meanings
- **CSV Export**: Export vocabulary to CSV (compatible with Anki import) via system share sheet
- **Dark Mode**: Full dark theme support with Material 3 design

## Pro Features

Mekuru is free and open source. Some features — like cloud-based manga OCR — require a one-time Pro unlock. Pro features are validated server-side and purchases go through Google Play Billing. OCR requires a self-hosted server — see the [custom server docs](docs/documentation/manga/custom-server.md) for setup instructions.

If you find Mekuru useful, purchasing Pro is the best way to support continued development.

## Roadmap

- Cloud sync for reading progress and vocabulary across devices

## Technology Stack

- **Framework**: [Flutter](https://flutter.dev/) (Dart)
- **State Management**: [Riverpod](https://riverpod.dev/) with code generation
- **Database**: [Drift](https://drift.simonbinder.eu/) (SQLite, type-safe)
- **EPUB Rendering**: [epub.js](https://github.com/futurepress/epub.js) with custom reader bridge via [InAppWebView](https://pub.dev/packages/flutter_inappwebview)
- **Japanese Analysis**: [MeCab](https://pub.dev/packages/mecab_for_flutter) (IPAdic morphological dictionary)

## Getting Started

### Prerequisites

- Flutter SDK 3.10.8 or later
- Android SDK (for Android builds)
- A connected Android device or emulator

### Installation

```bash
# Clone the repository
git clone https://github.com/mostrowski123/japanese-e-reader.git
cd japanese-e-reader

# Install dependencies
flutter pub get

# Run code generation (Drift database + Riverpod providers)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run
```

### Running Tests

```bash
flutter test
```

## Project Structure

```
lib/
├── core/                  # Database, utilities, shared infrastructure
├── features/
│   ├── library/           # Book import, EPUB parsing, library grid UI
│   ├── reader/            # EPUB viewer, MeCab, compound word resolution, settings
│   ├── manga/             # Manga viewer, OCR, Pro billing
│   ├── dictionary/        # Yomitan import, query engine, dictionary management
│   ├── vocabulary/        # Saved words, CSV export, vocabulary list UI
│   └── settings/          # App preferences, OCR server config
└── shared/                # Theme definitions, shared widgets
```

Each feature follows `data/` (models, repositories, services) and `presentation/` (screens, widgets, providers).

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Run tests (`flutter test`) and analysis (`flutter analyze`)
5. Commit and push
6. Open a Pull Request

See [CLAUDE.md](CLAUDE.md) for codebase conventions and architecture details.

## License

This project is licensed under the GNU Affero General Public License v3.0. See the [LICENSE](LICENSE) file for details.
