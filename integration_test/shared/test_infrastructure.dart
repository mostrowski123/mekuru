import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;

import '../../test/test_app.dart';

// ──────────────── In-Memory Storage ────────────────

/// In-memory implementation of [AppSettingsStorage] for integration tests.
/// Avoids SharedPreferences dependency while still testing provider wiring.
class InMemoryAppSettingsStorage implements AppSettingsStorage {
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
  Future<void> saveAppLanguage(AppLanguage language) async =>
      _appLanguage = language;

  @override
  Future<ThemeMode?> loadThemeMode() async => _themeMode;
  @override
  Future<void> saveThemeMode(ThemeMode mode) async => _themeMode = mode;

  @override
  Future<String?> loadSortOrder() async => _sortOrder;
  @override
  Future<void> saveSortOrder(String order) async => _sortOrder = order;

  @override
  Future<double?> loadLookupFontSize() async => _lookupFontSize;
  @override
  Future<void> saveLookupFontSize(double size) async => _lookupFontSize = size;

  @override
  Future<List<String>> loadSearchHistory() async => _searchHistory;
  @override
  Future<void> saveSearchHistory(List<String> history) async =>
      _searchHistory = List<String>.of(history);

  @override
  Future<bool?> loadFilterRomanLetters() async => _filterRomanLetters;
  @override
  Future<void> saveFilterRomanLetters(bool value) async =>
      _filterRomanLetters = value;

  @override
  Future<String?> loadAnkidroidConfig() async => _ankidroidConfig;
  @override
  Future<void> saveAnkidroidConfig(String configJson) async =>
      _ankidroidConfig = configJson;

  @override
  Future<String?> loadStartupScreen() async => _startupScreen;
  @override
  Future<void> saveStartupScreen(String screen) async =>
      _startupScreen = screen;

  @override
  Future<bool?> loadAutoFocusSearch() async => _autoFocusSearch;
  @override
  Future<void> saveAutoFocusSearch(bool value) async =>
      _autoFocusSearch = value;

  @override
  Future<String?> loadColorTheme() async => _colorTheme;
  @override
  Future<void> saveColorTheme(String theme) async => _colorTheme = theme;

  @override
  Future<int?> loadAutoCropWhiteThreshold() async => _autoCropWhiteThreshold;
  @override
  Future<void> saveAutoCropWhiteThreshold(int value) async =>
      _autoCropWhiteThreshold = value;

  @override
  Future<String?> loadOcrServerUrl() async => _ocrServerUrl;
  @override
  Future<void> saveOcrServerUrl(String url) async => _ocrServerUrl = url;
}

/// In-memory implementation of [ReaderSettingsStorage] for integration tests.
class InMemoryReaderSettingsStorage implements ReaderSettingsStorage {
  ReaderSettings? _settings;

  @override
  Future<ReaderSettings?> load() async => _settings;

  @override
  Future<void> save(ReaderSettings settings) async => _settings = settings;
}

// ──────────────── Database Seeding ────────────────

/// Creates an in-memory Drift database for integration tests.
AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

/// Seeds the database with 2 dictionaries and sample entries.
Future<void> seedDictionaries(AppDatabase db) async {
  // Insert dictionary metas.
  await db.into(db.dictionaryMetas).insert(
    DictionaryMetasCompanion.insert(name: 'JMdict', sortOrder: const Value(0)),
  );
  await db.into(db.dictionaryMetas).insert(
    DictionaryMetasCompanion.insert(
      name: 'Example Dictionary',
      sortOrder: const Value(1),
    ),
  );

  // Sample Japanese words with glossaries.
  final words = <(String expression, String reading, List<String> glossaries)>[
    ('食べる', 'たべる', ['to eat', 'to take (a meal)']),
    ('飲む', 'のむ', ['to drink', 'to swallow']),
    ('走る', 'はしる', ['to run', 'to dash']),
    ('読む', 'よむ', ['to read', 'to recite']),
    ('書く', 'かく', ['to write', 'to compose']),
    ('見る', 'みる', ['to see', 'to look at', 'to watch']),
    ('聞く', 'きく', ['to hear', 'to listen', 'to ask']),
    ('話す', 'はなす', ['to speak', 'to talk', 'to tell']),
    ('行く', 'いく', ['to go', 'to move (in a direction)']),
    ('来る', 'くる', ['to come', 'to arrive']),
    ('食べ物', 'たべもの', ['food', 'provisions']),
    ('飲み物', 'のみもの', ['drink', 'beverage']),
    ('大きい', 'おおきい', ['big', 'large', 'great']),
    ('小さい', 'ちいさい', ['small', 'little', 'tiny']),
    ('新しい', 'あたらしい', ['new', 'novel', 'recent']),
    ('古い', 'ふるい', ['old', 'aged', 'ancient']),
    ('日本語', 'にほんご', ['Japanese (language)']),
    ('英語', 'えいご', ['English (language)']),
    ('学校', 'がっこう', ['school']),
    ('先生', 'せんせい', ['teacher', 'master', 'doctor']),
  ];

  for (final (expression, reading, glossaries) in words) {
    // Insert into JMdict (id=1).
    await db.into(db.dictionaryEntries).insert(
      DictionaryEntriesCompanion.insert(
        expression: expression,
        reading: Value(reading),
        glossaries: jsonEncode(glossaries),
        dictionaryId: 1,
        definitionTags: const Value('v1'),
        termTags: const Value('P'),
      ),
    );
    // Insert into Example Dictionary (id=2) with alternate glossary.
    await db.into(db.dictionaryEntries).insert(
      DictionaryEntriesCompanion.insert(
        expression: expression,
        reading: Value(reading),
        glossaries: jsonEncode(['${glossaries.first} (alt)']),
        dictionaryId: 2,
      ),
    );
  }
}

/// Seeds the database with vocabulary (saved words).
Future<void> seedVocabulary(AppDatabase db, {int count = 5}) async {
  final words = <(String expression, String reading, List<String> glossaries,
      String context)>[
    ('食べる', 'たべる', ['to eat'], '毎日ご飯を食べる。'),
    ('飲む', 'のむ', ['to drink'], '水を飲む。'),
    ('走る', 'はしる', ['to run'], '公園で走る。'),
    ('食べ物', 'たべもの', ['food'], '美味しい食べ物が好きです。'),
    ('大きい', 'おおきい', ['big', 'large'], 'あの建物は大きい。'),
    ('読む', 'よむ', ['to read'], '本を読む。'),
    ('書く', 'かく', ['to write'], '手紙を書く。'),
    ('見る', 'みる', ['to see', 'to watch'], '映画を見る。'),
  ];

  for (var i = 0; i < count && i < words.length; i++) {
    final (expression, reading, glossaries, context) = words[i];
    await db.into(db.savedWords).insert(
      SavedWordsCompanion.insert(
        expression: expression,
        reading: Value(reading),
        glossaries: jsonEncode(glossaries),
        sentenceContext: Value(context),
      ),
    );
  }
}

/// Seeds the database with book metadata (no actual files needed).
Future<void> seedBooks(AppDatabase db, {int count = 3}) async {
  final books = <(String title, String filePath)>[
    ('吾輩は猫である', '/fake/path/wagahai.epub'),
    ('走れメロス', '/fake/path/melos.epub'),
    ('羅生門', '/fake/path/rashomon.epub'),
    ('坊っちゃん', '/fake/path/botchan.epub'),
    ('こころ', '/fake/path/kokoro.epub'),
  ];

  for (var i = 0; i < count && i < books.length; i++) {
    final (title, filePath) = books[i];
    await db.into(db.books).insert(
      BooksCompanion.insert(title: title, filePath: filePath),
    );
  }
}

// ──────────────── App Builder ────────────────

/// Builds a test app with standard provider overrides for integration tests.
///
/// The [home] widget is wrapped in a localized MaterialApp with ProviderScope.
Widget buildIntegrationTestApp({
  required AppDatabase db,
  required Widget home,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      appSettingsStorageProvider.overrideWithValue(InMemoryAppSettingsStorage()),
      readerSettingsStorageProvider.overrideWithValue(
        InMemoryReaderSettingsStorage(),
      ),
      proUnlockedProvider.overrideWithBuild((ref, notifier) => false),
      autoBackupCheckerProvider.overrideWith((ref) async {}),
    ],
    child: buildLocalizedTestApp(home: home),
  );
}
