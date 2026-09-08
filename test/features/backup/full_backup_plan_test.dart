import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/full_backup_plan.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:path/path.dart' as p;

/// The plan decides what a person finds after unzipping: only the files the
/// library actually references, under the titles they know, and nothing
/// from failed imports or the quarantine.
void main() {
  late Directory root;
  late Directory books;
  late String snapshotPath;

  File write(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  Future<void> seedSnapshot() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase(File(snapshotPath)));
    Future<void> book(
      String title,
      String dir, {
      String type = 'epub',
      String? cover,
      String? filePathOverride,
    }) => db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: title,
            filePath:
                filePathOverride ??
                (type == 'epub'
                    ? '${root.path}/books/$dir/content'
                    : '${root.path}/books/$dir'),
            bookType: Value(type),
            coverImagePath: Value(cover),
          ),
        );
    await book(
      '走れメロス',
      'book_1_aaaaaaaa',
      cover: '${root.path}/books/book_1_aaaaaaaa/content/cover.jpg',
    );
    await book('漫画: 第1巻', 'manga_2_bbbbbbbb', type: 'manga');
    await book(
      'External',
      'manga_3_cccccccc',
      type: 'manga',
      cover: 'content://tree/x/cover.jpg',
    );
    await book('走れメロス', 'book_4_dddddddd');
    await book('Missing on disk', 'manga_5_eeeeeeee', type: 'manga');
    final dictionaries = DictionaryRepository(db);
    await dictionaries.insertDictionary('JMdict');
    final hidden = await dictionaries.insertDictionary('Bundled frequency');
    await (db.update(db.dictionaryMetas)..where((t) => t.id.equals(hidden)))
        .write(const DictionaryMetasCompanion(isHidden: Value(true)));
    await db.close();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('plan_root_');
    books = Directory(p.join(root.path, 'books'))..createSync();
    snapshotPath = p.join(root.path, 'snapshot.sqlite');
    await seedSnapshot();

    write(p.join(books.path, 'book_1_aaaaaaaa', 'メロス.epub'), 'EPUB-BYTES');
    write(
      p.join(books.path, 'book_1_aaaaaaaa', 'content', 'ch1.xhtml'),
      '<p/>',
    );
    write(p.join(books.path, 'book_1_aaaaaaaa', 'content', 'cover.jpg'), 'J');
    write(p.join(books.path, 'book_1_aaaaaaaa', 'pages_cache.json.tmp'), 'x');
    write(p.join(books.path, 'manga_2_bbbbbbbb', '001.jpg'), 'IMG1');
    write(p.join(books.path, 'manga_2_bbbbbbbb', 'pages_cache.json'), '{}');
    write(p.join(books.path, 'manga_3_cccccccc', 'pages_cache.json'), '{}');
    write(p.join(books.path, 'book_4_dddddddd', 'content', 'a.xhtml'), 'A');
    write(p.join(books.path, 'book_9_99999999', 'orphan.epub'), 'ORPHAN');
    write(p.join(books.path, '.trash', '1_book_8', 'old.bin'), 'OLD');
    write(p.join(books.path, 'custom_cover_77.png'), 'PNG');
    write(p.join(books.path, 'scratch.tmp'), 'tmp');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  FullBackupPlan build() => buildExportPlan(
    BuildExportPlanArgs(snapshotDbPath: snapshotPath, booksDirPath: books.path),
  );

  test('maps claimed directories to titled folders and nothing else', () {
    final plan = build();

    expect(plan.folders, {
      'Books/走れメロス/': 'book_1_aaaaaaaa',
      'Books/走れメロス (2)/': 'book_4_dddddddd',
      'Manga/漫画 第1巻/': 'manga_2_bbbbbbbb',
      'Manga/External/': 'manga_3_cccccccc',
      'Manga/Missing on disk/': 'manga_5_eeeeeeee',
    });
    final names = plan.entries.map((e) => e.name).toList();
    expect(names, [
      'Mekuru data/covers/custom_cover_77.png',
      'Books/走れメロス/content/ch1.xhtml',
      'Books/走れメロス/content/cover.jpg',
      'Books/走れメロス/メロス.epub',
      'Books/走れメロス (2)/content/a.xhtml',
      'Manga/漫画 第1巻/001.jpg',
      'Manga/漫画 第1巻/pages_cache.json',
      'Manga/External/pages_cache.json',
    ]);
    expect(names.any((n) => n.contains('orphan')), isFalse);
    expect(names.any((n) => n.contains('.trash')), isFalse);
    expect(names.any((n) => n.endsWith('.tmp')), isFalse);
    expect(plan.entries.every((e) => e.level == 0), isTrue);
  });

  test('sizes, counts and paths come from the snapshot and the disk', () {
    final plan = build();

    expect(plan.bookCount, 5);
    expect(plan.dictionaryCount, 1);
    expect(plan.externalMangaCount, 1);
    final epub = plan.entries.singleWhere((e) => e.name.endsWith('メロス.epub'));
    expect(epub.path, p.join(books.path, 'book_1_aaaaaaaa', 'メロス.epub'));
    expect(epub.size, 'EPUB-BYTES'.length);
    expect(
      plan.booksBytes,
      plan.entries.fold<int>(0, (sum, e) => sum + e.size),
    );
    expect(plan.booksBytes, 10 + 4 + 1 + 1 + 4 + 2 + 2 + 3);
  });

  test('a missing books directory yields an empty payload', () {
    books.deleteSync(recursive: true);
    final plan = build();
    expect(plan.entries, isEmpty);
    expect(plan.folders, isNotEmpty);
  });

  test('plan lines carry exactly what the native job reads', () {
    const entry = FullBackupPlanEntry(
      path: '/a/b.epub',
      name: 'Books/x/b.epub',
      size: 12,
      level: 0,
    );
    expect(
      entry.toJsonLine(),
      '{"p":"/a/b.epub","n":"Books/x/b.epub","s":12,"l":0}',
    );
  });

  test('the readme names the layout and the restore path', () {
    final text = fullBackupReadme(
      appVersion: '1.38.0',
      createdAt: DateTime.utc(2026, 9, 8, 10),
    );
    expect(text, contains('Created 2026-09-08 with Mekuru 1.38.0'));
    for (final part in [
      'Books/',
      'Manga/',
      'Mekuru data/',
      FullBackupManifest.manifestEntry,
      'Restore full backup (.zip)',
      'replaces everything in Mekuru',
    ]) {
      expect(text, contains(part));
    }
    expect(text, isNot(contains('device will be')));
  });
}
