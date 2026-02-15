import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/compound_word_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/main.dart';

final readerSettingsStorageProvider = Provider<ReaderSettingsStorage>((ref) {
  return SharedPreferencesReaderSettingsStorage();
});

/// Manages reader display settings.
class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  bool _hasLoadedPersistedSettings = false;

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
  }

  void toggleVerticalText() {
    setVerticalText(!state.verticalText);
  }

  void setReadingDirection(ReaderDirection direction) {
    state = state.copyWith(readingDirection: direction);
    _persistSettings();
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

  void _persistSettings() {
    unawaited(ref.read(readerSettingsStorageProvider).save(state));
  }
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
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
