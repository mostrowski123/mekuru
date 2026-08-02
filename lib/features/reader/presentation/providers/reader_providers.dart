import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/reader/data/models/book_reading_config.dart';
import 'package:mekuru/features/reader/data/models/reader_brightness_state.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/compound_word_resolver.dart';
import 'package:mekuru/features/reader/data/repositories/bookmark_repository.dart';
import 'package:mekuru/features/reader/data/repositories/highlight_repository.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/main.dart';
import 'package:screen_brightness/screen_brightness.dart';

final readerSettingsStorageProvider = Provider<ReaderSettingsStorage>((ref) {
  return SharedPreferencesReaderSettingsStorage();
});

/// Manages reader display settings.
///
/// Settings are split into two layers:
/// - **Global** settings (font size, color mode, margins, etc.) are stored in
///   SharedPreferences and shared across all books.
/// - **Per-book** overrides (`verticalText`, `readingDirection`) are stored in
///   the Books table and remembered for each book individually.
class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  bool _hasLoadedPersistedSettings = false;

  /// The currently-open book's ID (set by [applyBookDefaults]).
  /// Used to persist per-book overrides when the user changes
  /// verticalText or readingDirection.
  int? _currentBookId;

  @override
  ReaderSettings build() => const ReaderSettings();

  Future<void> loadPersistedSettings() async {
    if (_hasLoadedPersistedSettings) {
      return;
    }

    _hasLoadedPersistedSettings = true;
    final persistedSettings = await ref
        .read(readerSettingsStorageProvider)
        .load();
    if (persistedSettings != null) {
      state = persistedSettings;
    }
  }

  /// Applies [next], persists it globally, and — this is the single place
  /// the global vs. per-book split is enforced — writes per-book overrides
  /// whenever one of the per-book fields (verticalText, readingDirection,
  /// furiganaMode) changed while a book is open.
  void _update(ReaderSettings next) {
    final perBookFieldChanged =
        next.verticalText != state.verticalText ||
        next.readingDirection != state.readingDirection ||
        next.furiganaMode != state.furiganaMode;
    state = next;
    _persistSettings();
    if (perBookFieldChanged) {
      _persistPerBookOverrides();
    }
  }

  void setFontSize(double size) {
    _update(state.copyWith(fontSize: size));
  }

  void setVerticalText(bool enabled) {
    _update(state.copyWith(verticalText: enabled));
  }

  void toggleVerticalText() {
    setVerticalText(!state.verticalText);
  }

  void setSplitVerticalText(bool enabled) {
    _update(state.copyWith(splitVerticalText: enabled));
  }

  void setReadingDirection(ReaderDirection direction) {
    _update(state.copyWith(readingDirection: direction));
  }

  void setHorizontalPadding(int padding) {
    _update(state.copyWith(horizontalPadding: padding));
  }

  void setVerticalPadding(int padding) {
    _update(state.copyWith(verticalPadding: padding));
  }

  void setSwipeSensitivity(double sensitivity) {
    _update(state.copyWith(swipeSensitivity: sensitivity));
  }

  void setMangaPageTurnEdgeZoneWidthFraction(double widthFraction) {
    _update(
      state.copyWith(
        mangaPageTurnEdgeZoneWidthFraction:
            clampMangaPageTurnEdgeZoneWidthFraction(widthFraction),
      ),
    );
  }

  void setMangaViewMode(MangaViewMode mode) {
    _update(state.copyWith(mangaViewMode: mode));
  }

  void setMangaReadingDirection(ReaderDirection direction) {
    _update(state.copyWith(mangaReadingDirection: direction));
  }

  void setMangaAutoCrop(bool enabled) {
    _update(state.copyWith(mangaAutoCrop: enabled));
  }

  void setMangaTransparentLookup(bool transparent) {
    _update(state.copyWith(mangaTransparentLookup: transparent));
  }

  void setColorMode(ColorMode mode) {
    _update(state.copyWith(colorMode: mode));
  }

  void setKeepScreenOn(bool enabled) {
    _update(state.copyWith(keepScreenOn: enabled));
  }

  void setSepiaIntensity(double intensity) {
    _update(state.copyWith(sepiaIntensity: intensity));
  }

  void setDisableLinks(bool disabled) {
    _update(state.copyWith(disableLinks: disabled));
  }

  /// Sets the brightness override; `null` means follow the system brightness.
  void setBrightness(double? value) {
    _update(
      value == null
          ? state.copyWith(clearBrightness: true)
          : state.copyWith(brightness: value),
    );
  }

  void setFuriganaMode(FuriganaMode mode) {
    _update(state.copyWith(furiganaMode: mode));
  }

  /// Apply book-specific defaults when opening a book.
  ///
  /// Uses per-book overrides from the database if the user has previously
  /// changed the display settings for this book. Otherwise falls back to
  /// defaults derived from the book's language and page-progression-direction.
  ///
  /// Deliberately bypasses [_update]: it does NOT persist anything — only
  /// sets the in-memory state and tracks [bookId] for future per-book
  /// persistence.
  void applyBookDefaults({
    required int bookId,
    String? language,
    String? pageProgressionDirection,
    String? primaryWritingMode,
    bool? overrideVerticalText,
    String? overrideReadingDirection,
    String? overrideFuriganaMode,
  }) {
    _currentBookId = bookId;

    final effectiveVerticalText =
        overrideVerticalText ??
        defaultVerticalText(
          language: language,
          pageProgressionDirection: pageProgressionDirection,
          primaryWritingMode: primaryWritingMode,
        );

    final effectiveDirection = overrideReadingDirection != null
        ? readerDirectionFromString(overrideReadingDirection)
        : defaultReaderDirection(
            language: language,
            pageProgressionDirection: pageProgressionDirection,
          );

    final effectiveFuriganaMode = overrideFuriganaMode != null
        ? furiganaModeFromString(overrideFuriganaMode)
        : state.furiganaMode;

    state = state.copyWith(
      verticalText: effectiveVerticalText,
      readingDirection: effectiveDirection,
      furiganaMode: effectiveFuriganaMode,
    );
  }

  /// Clears the book scoped by [applyBookDefaults] so later global settings
  /// changes (e.g. from the settings screen) cannot write per-book overrides
  /// to a book that is no longer open.
  void clearCurrentBook() {
    _currentBookId = null;
  }

  void _persistSettings() {
    unawaited(ref.read(readerSettingsStorageProvider).save(state));
  }

  /// Persist the current verticalText and readingDirection as per-book
  /// overrides in the database so they are remembered next time the book
  /// is opened.
  void _persistPerBookOverrides() {
    final bookId = _currentBookId;
    if (bookId == null) return;

    unawaited(
      ref
          .read(readerBookRepositoryProvider)
          .updateDisplayOverrides(
            bookId,
            verticalText: state.verticalText,
            readingDirection: state.readingDirection.storageValue,
            furiganaMode: Value(state.furiganaMode.storageValue),
          ),
    );
  }
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );

/// Applies the persisted brightness override while a reader is open and
/// restores the system brightness when it closes.
class ReaderBrightnessNotifier extends Notifier<ReaderBrightnessState> {
  /// Last device brightness read; survives [build] re-runs because Riverpod
  /// retains the notifier instance.
  double _systemLevel = 0.5;

  @override
  ReaderBrightnessState build() {
    final override = ref.watch(
      readerSettingsProvider.select((settings) => settings.brightness),
    );
    return ReaderBrightnessState(override: override, systemLevel: _systemLevel);
  }

  /// Reads the device brightness (for slider positioning) and applies the
  /// persisted override, if any. Call from a reader screen's initState.
  Future<void> applyForReaderOpen() async {
    try {
      _systemLevel = await ScreenBrightness.instance.system;
    } catch (e) {
      debugPrint('[Brightness] failed to read system brightness: $e');
      try {
        _systemLevel = await ScreenBrightness.instance.application;
      } catch (e) {
        debugPrint('[Brightness] failed to read current brightness: $e');
        _systemLevel = 0.5;
      }
    }
    final override = state.override;
    state = ReaderBrightnessState(
      override: override,
      systemLevel: _systemLevel,
    );
    if (override != null) {
      await _setApplicationBrightness(override);
    }
  }

  /// Applies [value] to the screen and slider WITHOUT persisting — for live
  /// slider drags, where persisting every tick would spam SharedPreferences.
  /// Call [setBrightness] with the final value on drag end.
  Future<void> previewBrightness(double value) async {
    state = ReaderBrightnessState(override: value, systemLevel: _systemLevel);
    await _setApplicationBrightness(value);
  }

  Future<void> setBrightness(double value) async {
    ref.read(readerSettingsProvider.notifier).setBrightness(value);
    await _setApplicationBrightness(value);
  }

  /// Clears the override and returns control to the system brightness.
  Future<void> followSystemBrightness() async {
    ref.read(readerSettingsProvider.notifier).setBrightness(null);
    await resetBrightness();
  }

  /// Restores the system brightness without clearing the persisted override.
  /// Call from a reader screen's dispose.
  Future<void> resetBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('[Brightness] failed to reset brightness: $e');
    }
  }

  Future<void> _setApplicationBrightness(double value) async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(value);
    } catch (e) {
      debugPrint('[Brightness] failed to set brightness: $e');
    }
  }
}

final readerBrightnessProvider =
    NotifierProvider<ReaderBrightnessNotifier, ReaderBrightnessState>(
      ReaderBrightnessNotifier.new,
    );

/// Provider for the MeCab morphological analysis service.
final mecabServiceProvider = Provider<MecabService>((ref) {
  return MecabService.instance;
});

/// Provider for compound word resolution (tries longer dictionary matches).
final compoundWordResolverProvider = Provider<CompoundWordResolver>((ref) {
  final queryService = ref.watch(dictionaryQueryServiceProvider);
  return CompoundWordResolver(queryService);
});

/// Provider for the BookRepository (shared with library).
final readerBookRepositoryProvider = Provider<BookRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return BookRepository(db);
});

/// Provider for the BookmarkRepository.
final bookmarkRepositoryProvider = Provider<BookmarkRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return BookmarkRepository(db);
});

/// Provider for the HighlightRepository.
final highlightRepositoryProvider = Provider<HighlightRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return HighlightRepository(db);
});

/// Reactive stream of bookmarks for a specific book.
final bookmarksForBookProvider = StreamProvider.family<List<Bookmark>, int>((
  ref,
  bookId,
) {
  return ref.watch(bookmarkRepositoryProvider).watchBookmarksForBook(bookId);
});

/// Reactive stream of highlights for a specific book.
final highlightsForBookProvider = StreamProvider.family<List<Highlight>, int>((
  ref,
  bookId,
) {
  return ref.watch(highlightRepositoryProvider).watchHighlightsForBook(bookId);
});
