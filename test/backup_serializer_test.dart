import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';

void main() {
  BackupManifest buildManifest({
    int version = 1,
    List<BackupDictionaryPreference>? dictionaryPreferences,
    List<BackupSavedWordEntry>? savedWords,
    List<BackupBookEntry>? books,
    Map<String, dynamic>? appSettings,
    Map<String, dynamic>? readerSettings,
  }) {
    return BackupManifest(
      version: version,
      createdAt: DateTime.utc(2026, 3, 5, 14, 30),
      settings: BackupSettings(
        app: appSettings ?? {'app.theme_mode': 'dark'},
        reader: readerSettings ?? {'reader.font_size': 18.0},
      ),
      dictionaryPreferences: dictionaryPreferences ?? const [],
      savedWords: savedWords ?? [],
      books: books ?? [],
    );
  }

  group('BackupSerializer', () {
    test('round-trips a full manifest with books, bookmarks, highlights', () {
      final manifest = buildManifest(
        appSettings: {
          'app.theme_mode': 'dark',
          'app.color_theme': 'mekuruRed',
          'app.library_sort_order': 'dateAdded',
        },
        readerSettings: {
          'reader.font_size': 20.0,
          'reader.keep_screen_on': true,
        },
        dictionaryPreferences: const [
          BackupDictionaryPreference(
            name: 'JMdict',
            sortOrder: 0,
            isEnabled: true,
          ),
          BackupDictionaryPreference(
            name: 'Pitch Accent',
            sortOrder: 1,
            isEnabled: false,
          ),
        ],
        savedWords: [
          BackupSavedWordEntry(
            expression: '食べる',
            reading: 'たべる',
            glossaries: jsonEncode(['to eat']),
            sentenceContext: '昨日ケーキを食べた。',
            dateAdded: DateTime.utc(2026, 1, 15, 10),
          ),
        ],
        books: [
          BackupBookEntry(
            bookKey: 'epub::食べることの哲学',
            title: '食べることの哲学',
            bookType: 'epub',
            language: 'ja',
            pageProgressionDirection: 'rtl',
            primaryWritingMode: 'vertical-rl',
            lastReadCfi: 'epubcfi(/6/4!/4/2/1:0)',
            readProgress: 0.45,
            overrideVerticalText: true,
            overrideReadingDirection: 'rtl',
            bookmarks: [
              BackupBookmarkEntry(
                cfi: 'epubcfi(/6/8!/4/2/1:0)',
                progress: 0.12,
                chapterTitle: 'Chapter 3',
                userNote: 'important passage',
                dateAdded: DateTime.utc(2026, 2, 10, 8),
              ),
            ],
            highlights: [
              BackupHighlightEntry(
                cfiRange: 'epubcfi(/6/4!/4/2,/1:0,/1:15)',
                selectedText: '哲学とは何か',
                color: 'blue',
                userNote: 'key concept',
                dateAdded: DateTime.utc(2026, 2, 11, 9),
              ),
            ],
          ),
        ],
      );

      final json = BackupSerializer.encode(manifest);
      final decoded = BackupSerializer.decode(json);

      expect(decoded.version, 1);
      expect(decoded.createdAt, DateTime.utc(2026, 3, 5, 14, 30));

      // Settings
      expect(decoded.settings.app['app.theme_mode'], 'dark');
      expect(decoded.settings.app['app.color_theme'], 'mekuruRed');
      expect(decoded.settings.reader['reader.font_size'], 20.0);
      expect(decoded.settings.reader['reader.keep_screen_on'], true);
      expect(decoded.dictionaryPreferences, hasLength(2));
      expect(decoded.dictionaryPreferences[0].name, 'JMdict');
      expect(decoded.dictionaryPreferences[1].isEnabled, isFalse);

      // Saved words
      expect(decoded.savedWords, hasLength(1));
      expect(decoded.savedWords[0].expression, '食べる');
      expect(decoded.savedWords[0].reading, 'たべる');
      expect(decoded.savedWords[0].glossaries, jsonEncode(['to eat']));
      expect(decoded.savedWords[0].sentenceContext, '昨日ケーキを食べた。');

      // Books
      expect(decoded.books, hasLength(1));
      final book = decoded.books[0];
      expect(book.bookKey, 'epub::食べることの哲学');
      expect(book.title, '食べることの哲学');
      expect(book.bookType, 'epub');
      expect(book.language, 'ja');
      expect(book.readProgress, 0.45);
      expect(book.overrideVerticalText, true);
      expect(book.overrideReadingDirection, 'rtl');

      // Bookmarks
      expect(book.bookmarks, hasLength(1));
      expect(book.bookmarks[0].cfi, 'epubcfi(/6/8!/4/2/1:0)');
      expect(book.bookmarks[0].chapterTitle, 'Chapter 3');
      expect(book.bookmarks[0].userNote, 'important passage');

      // Highlights
      expect(book.highlights, hasLength(1));
      expect(book.highlights[0].selectedText, '哲学とは何か');
      expect(book.highlights[0].color, 'blue');
    });

    test('round-trips empty manifest (no books, no words)', () {
      final manifest = buildManifest();
      final json = BackupSerializer.encode(manifest);
      final decoded = BackupSerializer.decode(json);

      expect(decoded.savedWords, isEmpty);
      expect(decoded.books, isEmpty);
      expect(decoded.version, 1);
    });

    test('handles nullable fields (overrideVerticalText, language, etc.)', () {
      final manifest = buildManifest(
        books: [
          const BackupBookEntry(
            bookKey: 'epub::test book',
            title: 'Test Book',
            bookType: 'epub',
            language: null,
            pageProgressionDirection: null,
            primaryWritingMode: null,
            lastReadCfi: null,
            readProgress: 0.0,
            overrideVerticalText: null,
            overrideReadingDirection: null,
            bookmarks: [],
            highlights: [],
          ),
        ],
      );

      final json = BackupSerializer.encode(manifest);
      final decoded = BackupSerializer.decode(json);

      final book = decoded.books[0];
      expect(book.language, isNull);
      expect(book.lastReadCfi, isNull);
      expect(book.overrideVerticalText, isNull);
      expect(book.overrideReadingDirection, isNull);
    });

    test('preserves Japanese text (UTF-8) through round-trip', () {
      final manifest = buildManifest(
        savedWords: [
          BackupSavedWordEntry(
            expression: '新しい世界へようこそ',
            reading: 'あたらしいせかいへようこそ',
            glossaries: jsonEncode(['welcome to a new world']),
            sentenceContext: '新しい世界へようこそ！冒険が始まる。',
            dateAdded: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      final json = BackupSerializer.encode(manifest);
      final decoded = BackupSerializer.decode(json);

      expect(decoded.savedWords[0].expression, '新しい世界へようこそ');
      expect(decoded.savedWords[0].reading, 'あたらしいせかいへようこそ');
      expect(decoded.savedWords[0].sentenceContext, '新しい世界へようこそ！冒険が始まる。');
    });

    test('preserves timestamps accurately (UTC)', () {
      final timestamp = DateTime.utc(2026, 6, 15, 23, 59, 59);
      final manifest = buildManifest(
        savedWords: [
          BackupSavedWordEntry(
            expression: 'test',
            reading: '',
            glossaries: '[]',
            sentenceContext: '',
            dateAdded: timestamp,
          ),
        ],
      );

      final json = BackupSerializer.encode(manifest);
      final decoded = BackupSerializer.decode(json);

      expect(decoded.savedWords[0].dateAdded, timestamp);
    });

    test('rejects future version numbers with BackupVersionException', () {
      final json = jsonEncode({
        'version': 99,
        'appName': 'mekuru',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'settings': {'app': {}, 'reader': {}},
        'savedWords': [],
        'books': [],
      });

      expect(
        () => BackupSerializer.decode(json),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('decodes backups without dictionary preferences', () {
      final json = jsonEncode({
        'version': 1,
        'appName': 'mekuru',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'settings': {
          'app': {'app.theme_mode': 'dark'},
          'reader': {'reader.font_size': 18.0},
        },
        'savedWords': [],
        'books': [],
      });

      final decoded = BackupSerializer.decode(json);
      expect(decoded.dictionaryPreferences, isEmpty);
    });

    test('rejects malformed JSON with BackupFormatException', () {
      expect(
        () => BackupSerializer.decode('not json at all'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects JSON array instead of object', () {
      expect(
        () => BackupSerializer.decode('[]'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects missing version field', () {
      final json = jsonEncode({
        'appName': 'mekuru',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'settings': {'app': {}, 'reader': {}},
        'savedWords': [],
        'books': [],
      });

      expect(
        () => BackupSerializer.decode(json),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects missing settings field', () {
      final json = jsonEncode({
        'version': 1,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'savedWords': [],
        'books': [],
      });

      expect(
        () => BackupSerializer.decode(json),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('encodeBookEntry / decodeBookEntry round-trips', () {
      const entry = BackupBookEntry(
        bookKey: 'manga::test manga',
        title: 'Test Manga',
        bookType: 'manga',
        readProgress: 0.75,
        bookmarks: [],
        highlights: [],
      );

      final json = BackupSerializer.encodeBookEntry(entry);
      final decoded = BackupSerializer.decodeBookEntry(json);

      expect(decoded.bookKey, 'manga::test manga');
      expect(decoded.title, 'Test Manga');
      expect(decoded.bookType, 'manga');
      expect(decoded.readProgress, 0.75);
    });
  });
}
