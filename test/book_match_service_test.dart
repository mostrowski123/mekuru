import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/services/book_match_service.dart';
import 'package:path/path.dart' as p;

AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

void main() {
  final service = BookMatchService();

  group('BookMatchService.generateKey', () {
    test('normalizes title to lowercase and trims whitespace', () {
      expect(
        service.generateKey('  My Book Title  ', 'epub'),
        'epub::my book title',
      );
    });

    test('distinguishes epub vs manga for the same title', () {
      final epubKey = service.generateKey('Test Book', 'epub');
      final mangaKey = service.generateKey('Test Book', 'manga');
      expect(epubKey, isNot(mangaKey));
      expect(epubKey, 'epub::test book');
      expect(mangaKey, 'manga::test book');
    });

    test('handles Japanese titles', () {
      expect(service.generateKey('食べることの哲学', 'epub'), 'epub::食べることの哲学');
    });

    test('handles empty title', () {
      expect(service.generateKey('', 'epub'), 'epub::');
    });
  });

  group('BookMatchService.findMatch', () {
    late AppDatabase db;
    late Directory tempDir;

    setUp(() async {
      db = createTestDatabase();
      tempDir = await Directory.systemTemp.createTemp('book_match_service_');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('findLegacyMatch returns matching book when key matches', () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'My Great Book',
              filePath: '/fake/path',
            ),
          );

      final books = await db.select(db.books).get();
      final match = service.findLegacyMatch('epub::my great book', books);

      expect(match, isNotNull);
      expect(match!.title, 'My Great Book');
    });

    test('findLegacyMatch returns null when no match found', () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'Different Book',
              filePath: '/fake/path',
            ),
          );

      final books = await db.select(db.books).get();
      final match = service.findLegacyMatch('epub::nonexistent', books);

      expect(match, isNull);
    });

    test('findLegacyMatch matches are case-insensitive', () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'UPPERCASE TITLE',
              filePath: '/fake/path',
            ),
          );

      final books = await db.select(db.books).get();
      final match = service.findLegacyMatch('epub::uppercase title', books);

      expect(match, isNotNull);
    });

    test('findLegacyMatch does not match different bookType', () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'Test Book',
              filePath: '/fake/path',
              // bookType defaults to 'epub'
            ),
          );

      final books = await db.select(db.books).get();
      final match = service.findLegacyMatch('manga::test book', books);

      expect(match, isNull);
    });

    test(
      'generateHashKeyForPath returns same key for identical content',
      () async {
        final dir1 = Directory(p.join(tempDir.path, 'book1'))..createSync();
        final dir2 = Directory(p.join(tempDir.path, 'book2'))..createSync();
        File(p.join(dir1.path, 'a.txt')).writeAsStringSync('same');
        File(p.join(dir2.path, 'a.txt')).writeAsStringSync('same');

        final key1 = await service.generateHashKeyForPath(dir1.path, 'epub');
        final key2 = await service.generateHashKeyForPath(dir2.path, 'epub');

        expect(key1, isNotNull);
        expect(key2, isNotNull);
        expect(key1, key2);
        expect(service.isHashKey(key1!), isTrue);
      },
    );

    test(
      'generateHashKeyForPath returns different keys for different content',
      () async {
        final dir1 = Directory(p.join(tempDir.path, 'book1'))..createSync();
        final dir2 = Directory(p.join(tempDir.path, 'book2'))..createSync();
        File(p.join(dir1.path, 'a.txt')).writeAsStringSync('one');
        File(p.join(dir2.path, 'a.txt')).writeAsStringSync('two');

        final key1 = await service.generateHashKeyForPath(dir1.path, 'epub');
        final key2 = await service.generateHashKeyForPath(dir2.path, 'epub');

        expect(key1, isNotNull);
        expect(key2, isNotNull);
        expect(key1, isNot(key2));
      },
    );

    test('buildHashIndex maps hash key to the matching book', () async {
      final dirPath = p.join(tempDir.path, 'book_hash_index');
      final dir = Directory(dirPath)..createSync();
      File(p.join(dir.path, 'content.txt')).writeAsStringSync('content');

      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(title: 'Hashable Book', filePath: dir.path),
          );

      final books = await db.select(db.books).get();
      final index = await service.buildHashIndex(books);
      final key = await service.generateHashKeyForPath(dir.path, 'epub');

      expect(key, isNotNull);
      expect(index[key!], isNotNull);
      expect(index[key]!.title, 'Hashable Book');
    });
  });
}
