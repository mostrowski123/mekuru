import 'dart:convert';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;

import '../test/test_app.dart';

class _InMemoryAppSettingsStorage implements AppSettingsStorage {
  AppLanguage? _appLanguage;
  ThemeMode? _themeMode;
  String? _sortOrder;
  double? _lookupFontSize;
  List<String> _searchHistory = const [];
  bool? _filterRomanLetters;
  String? _ankidroidConfig;
  String? _startupScreen;
  bool? _autoFocusSearch;
  String? _colorTheme;
  int? _autoCropWhiteThreshold;
  String? _ocrServerUrl;

  @override
  Future<AppLanguage?> loadAppLanguage() async => _appLanguage;

  @override
  Future<void> saveAppLanguage(AppLanguage language) async {
    _appLanguage = language;
  }

  @override
  Future<ThemeMode?> loadThemeMode() async => _themeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    _themeMode = mode;
  }

  @override
  Future<String?> loadSortOrder() async => _sortOrder;

  @override
  Future<void> saveSortOrder(String order) async {
    _sortOrder = order;
  }

  @override
  Future<double?> loadLookupFontSize() async => _lookupFontSize;

  @override
  Future<void> saveLookupFontSize(double size) async {
    _lookupFontSize = size;
  }

  @override
  Future<List<String>> loadSearchHistory() async => _searchHistory;

  @override
  Future<void> saveSearchHistory(List<String> history) async {
    _searchHistory = List<String>.of(history);
  }

  @override
  Future<bool?> loadFilterRomanLetters() async => _filterRomanLetters;

  @override
  Future<void> saveFilterRomanLetters(bool value) async {
    _filterRomanLetters = value;
  }

  @override
  Future<String?> loadAnkidroidConfig() async => _ankidroidConfig;

  @override
  Future<void> saveAnkidroidConfig(String configJson) async {
    _ankidroidConfig = configJson;
  }

  @override
  Future<String?> loadStartupScreen() async => _startupScreen;

  @override
  Future<void> saveStartupScreen(String screen) async {
    _startupScreen = screen;
  }

  @override
  Future<bool?> loadAutoFocusSearch() async => _autoFocusSearch;

  @override
  Future<void> saveAutoFocusSearch(bool value) async {
    _autoFocusSearch = value;
  }

  @override
  Future<String?> loadColorTheme() async => _colorTheme;

  @override
  Future<void> saveColorTheme(String theme) async {
    _colorTheme = theme;
  }

  @override
  Future<int?> loadAutoCropWhiteThreshold() async => _autoCropWhiteThreshold;

  @override
  Future<void> saveAutoCropWhiteThreshold(int value) async {
    _autoCropWhiteThreshold = value;
  }

  @override
  Future<String?> loadOcrServerUrl() async => _ocrServerUrl;

  @override
  Future<void> saveOcrServerUrl(String url) async {
    _ocrServerUrl = url;
  }
}

class _BenchmarkDictionaryQueryService extends DictionaryQueryService {
  _BenchmarkDictionaryQueryService(super.db, {required this.results});

  final List<DictionaryEntryWithSource> results;

  @override
  Future<List<DictionaryEntryWithSource>> fuzzySearchWithSource(
    String term,
  ) async {
    if (term == 'benchmark') {
      return results;
    }
    return const [];
  }

  @override
  Future<Map<String, List<PitchAccentResult>>> searchPitchAccentsBatch(
    Iterable<String> expressions,
  ) async {
    return {for (final expression in expressions) expression: const []};
  }
}

List<DictionaryEntryWithSource> _buildBenchmarkResults() {
  final results = <DictionaryEntryWithSource>[];
  var id = 1;

  for (var i = 0; i < 220; i++) {
    final expression = '単語$i';
    final reading = 'たんご$i';
    results.addAll([
      DictionaryEntryWithSource(
        entry: DictionaryEntry(
          id: id++,
          expression: expression,
          reading: reading,
          entryKind: DictionaryEntryKinds.regular,
          kanjiOnyomi: '',
          kanjiKunyomi: '',
          definitionTags: 'v1',
          rules: 'vt',
          termTags: 'P',
          glossaries: jsonEncode(['日本語 例文 補足 情報 語彙 説明', '関連 単語 表現 用法 注意']),
          dictionaryId: 1,
        ),
        dictionaryName: 'JMdict',
        frequencyRank: i + 1,
      ),
      DictionaryEntryWithSource(
        entry: DictionaryEntry(
          id: id++,
          expression: expression,
          reading: reading,
          entryKind: DictionaryEntryKinds.regular,
          kanjiOnyomi: '',
          kanjiKunyomi: '',
          definitionTags: 'adj-i',
          rules: '',
          termTags: '',
          glossaries: jsonEncode(['参考 日本語 追加 解説 用例', '慣用 表現 語感 使い方']),
          dictionaryId: 2,
        ),
        dictionaryName: 'Example Dictionary',
        frequencyRank: i + 1,
      ),
      DictionaryEntryWithSource(
        entry: DictionaryEntry(
          id: id++,
          expression: expression,
          reading: reading,
          entryKind: DictionaryEntryKinds.regular,
          kanjiOnyomi: '',
          kanjiKunyomi: '',
          definitionTags: '',
          rules: '',
          termTags: '',
          glossaries: jsonEncode(['補助 説明 日本語 単語 追加']),
          dictionaryId: 2,
        ),
        dictionaryName: 'Example Dictionary',
        frequencyRank: i + 1,
      ),
    ]);
  }

  return results;
}

Future<void> _runScrollLoops(
  WidgetTester tester,
  Finder scrollable, {
  int loops = 18,
}) async {
  for (var i = 0; i < loops; i++) {
    await tester.fling(scrollable, const Offset(0, -1600), 3500);
    await tester.pumpAndSettle();
    await tester.fling(scrollable, const Offset(0, 1600), 3500);
    await tester.pumpAndSettle();
  }
}

Future<void> _runDragLoops(
  WidgetTester tester,
  Finder scrollable, {
  int loops = 45,
}) async {
  for (var i = 0; i < loops; i++) {
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pump();
  }
  for (var i = 0; i < loops; i++) {
    await tester.drag(scrollable, const Offset(0, 240));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpBenchmarkApp(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  final service = _BenchmarkDictionaryQueryService(
    db,
    results: _buildBenchmarkResults(),
  );
  final dictionaries = [
    DictionaryMeta(
      id: 1,
      name: 'JMdict',
      isEnabled: true,
      dateImported: DateTime(2026, 3, 13),
      sortOrder: 0,
      isHidden: false,
    ),
    DictionaryMeta(
      id: 2,
      name: 'Example Dictionary',
      isEnabled: true,
      dateImported: DateTime(2026, 3, 13),
      sortOrder: 1,
      isHidden: false,
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dictionaryQueryServiceProvider.overrideWithValue(service),
        dictionariesProvider.overrideWith((ref) => Stream.value(dictionaries)),
        appSettingsStorageProvider.overrideWithValue(
          _InMemoryAppSettingsStorage(),
        ),
      ],
      child: buildLocalizedTestApp(
        home: const DictionarySearchScreen(initialQuery: 'benchmark'),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('dictionary search scroll benchmark', (tester) async {
    await _pumpBenchmarkApp(tester);

    final timings = <FrameTiming>[];
    final binding = WidgetsBinding.instance;
    final callback = timings.addAll;
    binding.addTimingsCallback(callback);

    final scrollable = find.byType(Scrollable).first;
    expect(scrollable, findsOneWidget);

    await _runScrollLoops(tester, scrollable, loops: 1);
    timings.clear();

    final flingStopwatch = Stopwatch()..start();
    await _runScrollLoops(tester, scrollable);
    flingStopwatch.stop();

    final dragStopwatch = Stopwatch()..start();
    await _runDragLoops(tester, scrollable);
    dragStopwatch.stop();

    await tester.pump(const Duration(milliseconds: 250));

    binding.removeTimingsCallback(callback);

    final result = <String, Object?>{
      'fling_elapsed_millis': flingStopwatch.elapsedMilliseconds,
      'drag_elapsed_millis': dragStopwatch.elapsedMilliseconds,
      'frame_count': timings.length,
      'frame_summary': timings.isEmpty
          ? null
          : FrameTimingSummarizer(timings).summary,
    };

    debugPrint('dictionary_scroll_benchmark ${jsonEncode(result)}');
  });
}
