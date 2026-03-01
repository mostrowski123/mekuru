import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/reader/data/models/book_reading_config.dart';
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

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
    _persistSettings();
  }

  void setVerticalText(bool enabled) {
    state = state.copyWith(verticalText: enabled);
    _persistSettings();
    _persistPerBookOverrides();
  }

  void toggleVerticalText() {
    setVerticalText(!state.verticalText);
  }

  void setReadingDirection(ReaderDirection direction) {
    state = state.copyWith(readingDirection: direction);
    _persistSettings();
    _persistPerBookOverrides();
  }

  void setPageTurnAnimationEnabled(bool enabled) {
    state = state.copyWith(pageTurnAnimationEnabled: enabled);
    _persistSettings();
  }

  void setHorizontalPadding(int padding) {
    state = state.copyWith(horizontalPadding: padding);
    _persistSettings();
  }

  void setVerticalPadding(int padding) {
    state = state.copyWith(verticalPadding: padding);
    _persistSettings();
  }

  void setSwipeSensitivity(double sensitivity) {
    state = state.copyWith(swipeSensitivity: sensitivity);
    _persistSettings();
  }

  void setColorMode(ColorMode mode) {
    state = state.copyWith(colorMode: mode);
    _persistSettings();
  }

  void setKeepScreenOn(bool enabled) {
    state = state.copyWith(keepScreenOn: enabled);
    _persistSettings();
  }

  void setSepiaIntensity(double intensity) {
    state = state.copyWith(sepiaIntensity: intensity);
    _persistSettings();
  }

  void setDisableLinks(bool disabled) {
    state = state.copyWith(disableLinks: disabled);
    _persistSettings();
  }

  /// Apply book-specific defaults when opening a book.
  ///
  /// Uses per-book overrides from the database if the user has previously
  /// changed the display settings for this book. Otherwise falls back to
  /// defaults derived from the book's language and page-progression-direction.
  ///
  /// Does NOT persist global settings — only sets the in-memory state and
  /// tracks [bookId] for future per-book persistence.
  void applyBookDefaults({
    required int bookId,
    String? language,
    String? pageProgressionDirection,
    String? primaryWritingMode,
    bool? overrideVerticalText,
    String? overrideReadingDirection,
  }) {
    _currentBookId = bookId;

    final effectiveVerticalText = overrideVerticalText ??
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

    state = state.copyWith(
      verticalText: effectiveVerticalText,
      readingDirection: effectiveDirection,
    );
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
      ref.read(readerBookRepositoryProvider).updateDisplayOverrides(
        bookId,
        verticalText: state.verticalText,
        readingDirection: state.readingDirection.storageValue,
      ),
    );
  }
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );

/// Ephemeral brightness level for the current reading session.
/// Initialized from the system brightness when first read.
class BrightnessNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  Future<void> initialize() async {
    if (state != null) return;
    try {
      final brightness = await ScreenBrightness.instance.current;
      state = brightness;
    } catch (e) {
      debugPrint('[Brightness] failed to read current brightness: $e');
      try {
        final brightness = await ScreenBrightness.instance.system;
        state = brightness;
      } catch (e) {
        debugPrint('[Brightness] failed to read system brightness: $e');
        state = 0.5;
      }
    }
  }

  Future<void> setBrightness(double value) async {
    state = value;
    try {
      await ScreenBrightness.instance.setScreenBrightness(value);
    } catch (e) {
      debugPrint('[Brightness] failed to set brightness: $e');
    }
  }

  Future<void> resetBrightness() async {
    try {
      await ScreenBrightness.instance.resetScreenBrightness();
    } catch (e) {
      debugPrint('[Brightness] failed to reset brightness: $e');
    }
  }
}

final brightnessProvider =
    NotifierProvider<BrightnessNotifier, double?>(BrightnessNotifier.new);

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
final bookmarksForBookProvider =
    StreamProvider.family<List<Bookmark>, int>((ref, bookId) {
  return ref.watch(bookmarkRepositoryProvider).watchBookmarksForBook(bookId);
});

/// Reactive stream of highlights for a specific book.
final highlightsForBookProvider =
    StreamProvider.family<List<Highlight>, int>((ref, bookId) {
  return ref.watch(highlightRepositoryProvider).watchHighlightsForBook(bookId);
});
