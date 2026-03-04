# Mekuru - Project Guide

## Overview

Mekuru (めくる — "to turn pages") is a Japanese-first EPUB and manga reader built with Flutter/Dart. It features vertical text rendering, a dedicated manga viewer with OCR support, offline Yomitan-compatible dictionary lookups, MeCab morphological analysis for word boundary detection, compound word resolution, and vocabulary management with Anki-compatible CSV export.

## Architecture

Feature-first modular structure:

```
lib/
├── core/                          # Shared infrastructure
│   ├── database/                  # Drift (SQLite) database definition
│   │   └── database_provider.dart # AppDatabase with 4 tables
│   ├── server/                    # Local HTTP server (stub)
│   └── utils/                     # Isolate helpers (stub)
├── features/
│   ├── library/                   # Book import, EPUB parsing, library UI
│   ├── reader/                    # EPUB viewer, MeCab, compound word resolution
│   ├── manga/                     # Manga viewer, OCR, Pro billing
│   ├── dictionary/                # Yomitan import, query engine, management UI
│   ├── vocabulary/                # Saved words, CSV export
│   └── settings/                  # App preferences, OCR server config
└── shared/
    ├── theme/                     # Light/dark Material 3 themes
    └── widgets/                   # Shared UI components
```

Each feature follows `data/` (models, repositories, services) and `presentation/` (screens, widgets, providers).

## State Management

Riverpod with code generation (`riverpod_annotation` + `riverpod_generator`). The global `databaseProvider` in `main.dart` provides the `AppDatabase` instance.

## Database

Drift (SQLite) with 4 tables: `Books`, `DictionaryMetas`, `DictionaryEntries`, `SavedWords`. Schema defined in `lib/core/database/database_provider.dart`. Glossaries are stored as raw JSON strings (no Drift type converters).

## Build & Test Commands

```bash
flutter pub get                                             # Install dependencies
dart run build_runner build --delete-conflicting-outputs    # Drift/Riverpod codegen
flutter test                                                # Run unit tests
flutter analyze                                             # Static analysis
flutter run                                                 # Run on connected device
```

## Testing Conventions

- In-memory Drift databases: `AppDatabase(NativeDatabase.memory())`
- Helper pattern: `createTestDatabase()` in test files
- Always close DB in tearDown: `tearDown(() async { await db.close(); })`
- Build test data inline (e.g., `DictionaryEntriesCompanion.insert(...)`)
- MeCab requires device assets — cannot be fully tested in unit tests
- `CompoundWordResolver` tests build `WordIdentification` objects manually (no MeCab needed)

## Key Patterns

- **MeCab**: Singleton at `MecabService.instance`, requires `init()` with device assets at app startup
- **Compound word resolution**: Greedy longest-match (up to 5 tokens) against dictionary via `hasMatch()`
- **Dictionary queries**: Always join with `DictionaryMetas` to filter by `isEnabled`
- **EPUB rendering**: Custom bridge (`assets/epub_viewer/reader_bridge.js`) communicating with Dart via `flutter_inappwebview`
- **Reader interaction logic**: Pure functions (no Flutter deps) in `reader_interaction_logic.dart` — fully unit-testable

## Key Files

| File | Purpose |
|------|---------|
| `lib/core/database/database_provider.dart` | Full database schema and connection |
| `lib/features/reader/presentation/screens/reader_screen.dart` | Main EPUB reader UI with WebView |
| `lib/features/library/data/services/epub_parser.dart` | EPUB unzipping and metadata extraction |
| `lib/features/dictionary/data/repositories/dictionary_repository.dart` | Dictionary CRUD operations |
| `lib/features/dictionary/data/services/dictionary_query_service.dart` | Dictionary lookup/search queries |
| `lib/features/dictionary/data/services/dictionary_importer.dart` | Yomitan ZIP import (runs in isolate) |
| `lib/features/reader/data/services/mecab_service.dart` | Japanese morphological analysis |
| `lib/features/reader/data/services/compound_word_resolver.dart` | Multi-token compound word matching |
| `lib/features/reader/presentation/reader_interaction_logic.dart` | Tap/swipe gesture resolution |
| `lib/features/vocabulary/data/repositories/vocabulary_repository.dart` | Saved words and CSV export |
| `lib/features/manga/presentation/providers/pro_access_provider.dart` | Pro unlock state (server-validated) |
| `lib/features/manga/data/services/ocr_billing_client.dart` | Firebase billing API client |
| `lib/features/settings/data/services/ocr_server_config.dart` | OCR server URL configuration |
