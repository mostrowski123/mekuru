import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../shared/fake_path_provider.dart';
import '../../shared/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookRepository repo;
  late Directory tempDir;
  late Directory booksRoot;

  setUp(() {
    db = createTestDatabase();
    repo = BookRepository(db);
    tempDir = Directory.systemTemp.createTempSync('orphan_sweep_test_');
    booksRoot = Directory(p.join(tempDir.path, 'books'));
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    BookRepository.inFlightImportDirNames.clear();
  });

  tearDown(() async {
    await db.close();
    BookRepository.inFlightImportDirNames.clear();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Windows can hold locks on freshly written files.
      }
    }
  });

  /// An import-dir name whose embedded timestamp is comfortably older than
  /// the default 7-day age gate.
  const ancientOrphan = 'book_1000_ab12cd34';

  Directory plantDir(String name) {
    final dir = Directory(p.join(booksRoot.path, name))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'junk.bin')).writeAsBytesSync([1, 2, 3]);
    return dir;
  }

  Future<int> insertEpub(String dirName) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          title: 'epub $dirName',
          filePath: p.join(booksRoot.path, dirName, 'content'),
        ),
      );

  Future<int> insertManga(String dirName, {String? coverImagePath}) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          title: 'manga $dirName',
          filePath: p.join(booksRoot.path, dirName),
          bookType: const Value('manga'),
          coverImagePath: Value(coverImagePath),
        ),
      );

  /// A live book so the empty-table guard doesn't abort the sweep.
  Future<void> seedLiveManga() async {
    plantDir('manga_1');
    await insertManga('manga_1');
  }

  List<String> trashEntryNames() {
    final trash = Directory(p.join(booksRoot.path, '.trash'));
    if (!trash.existsSync()) return const [];
    return trash.listSync().map((e) => p.basename(e.path)).toList();
  }

  group('claimedDirNames', () {
    test('yields the segment after every books component', () {
      expect(
        BookRepository.claimedDirNames(
          '/data/user/0/app/files/books/manga_5',
        ).toList(),
        ['manga_5'],
      );
      expect(
        BookRepository.claimedDirNames(
          '/data/user/0/app/files/books/book_5/content',
        ).toList(),
        ['book_5'],
      );
      expect(
        BookRepository.claimedDirNames(
          '/storage/emulated/0/books/Naruto/files/books/manga_2',
        ).toList(),
        ['Naruto', 'manga_2'],
      );
    });

    test('normalizes .. before splitting', () {
      expect(
        BookRepository.claimedDirNames(
          '/app/files/books/manga_1/../manga_2',
        ).toList(),
        ['manga_2'],
      );
    });

    test('yields nothing for paths without a books segment', () {
      expect(BookRepository.claimedDirNames('/elsewhere/manga_1'), isEmpty);
      expect(
        BookRepository.claimedDirNames('content://provider/tree/doc123'),
        isEmpty,
      );
    });
  });

  group('sweepOrphanImportDirs — detection', () {
    test('quarantines an old orphan with no referencing row', () async {
      await seedLiveManga();
      final orphan = plantDir(ancientOrphan);

      final swept = await repo.sweepOrphanImportDirs();

      expect(swept, 1);
      expect(orphan.existsSync(), isFalse);
      expect(trashEntryNames(), [
        matches(RegExp(r'^\d+_' + RegExp.escape(ancientOrphan) + r'$')),
      ]);
    });

    test('never touches a live EPUB dir, however old its name', () async {
      final dir = plantDir('book_1');
      Directory(p.join(dir.path, 'content')).createSync();
      await insertEpub('book_1');

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(dir.existsSync(), isTrue);
    });

    test('never touches a live manga dir, however old its name', () async {
      final dir = plantDir('manga_1');
      await insertManga('manga_1');

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(dir.existsSync(), isTrue);
    });

    test('a stale absolute prefix still protects the dir', () async {
      // After an Android backup restore the stored prefix no longer matches
      // the current data dir. Matching must be by segment, not prefix.
      final dir = plantDir('manga_7');
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'restored manga',
              filePath: '/data/user/99/other/files/books/manga_7',
              bookType: const Value('manga'),
            ),
          );

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(dir.existsSync(), isTrue);
    });

    test('does nothing when the books table is empty', () async {
      // Empty table + files on disk can mean the DB was lost while the
      // books survived — nothing may be treated as an orphan then.
      final orphan = plantDir(ancientOrphan);

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(orphan.existsSync(), isTrue);
      expect(trashEntryNames(), isEmpty);
    });

    test('aborts entirely when any row has an unparseable filePath', () async {
      await seedLiveManga();
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'weird row',
              filePath: '/elsewhere/manga_1',
            ),
          );
      final orphan = plantDir(ancientOrphan);

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(orphan.existsSync(), isTrue);
    });

    test('content:// cover URIs are tolerated', () async {
      final dir = plantDir('manga_1');
      await insertManga(
        'manga_1',
        coverImagePath: 'content://com.android.externalstorage/tree/doc%3A12',
      );

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(dir.existsSync(), isTrue);
    });

    test('a cover inside another import dir protects that dir', () async {
      await seedLiveManga();
      // A custom cover stored inside an otherwise-unreferenced dir.
      final coverDir = plantDir('book_2000_deadbeef');
      await insertManga(
        'manga_1',
        coverImagePath: p.join(coverDir.path, 'cover.jpg'),
      );

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(coverDir.existsSync(), isTrue);
    });

    test('loose files in books/ are never touched', () async {
      await seedLiveManga();
      final cover = File(p.join(booksRoot.path, 'custom_cover_1.jpg'))
        ..writeAsBytesSync([1, 2, 3]);

      await repo.sweepOrphanImportDirs();
      expect(cover.existsSync(), isTrue);
    });

    test('dirs with non-matching names are never touched', () async {
      await seedLiveManga();
      final other = plantDir('imports');
      final badPrefix = plantDir('book_abc');
      final trashItself = plantDir('.trash');

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(other.existsSync(), isTrue);
      expect(badPrefix.existsSync(), isTrue);
      expect(trashItself.existsSync(), isTrue);
    });

    test('missing books root is a no-op', () async {
      expect(await repo.sweepOrphanImportDirs(), 0);
    });

    test('a symlink named like an orphan is not followed or deleted', () async {
      await seedLiveManga();
      final target = Directory(p.join(tempDir.path, 'outside'))
        ..createSync(recursive: true);
      final link = Link(p.join(booksRoot.path, ancientOrphan));
      try {
        link.createSync(target.path);
      } on FileSystemException {
        markTestSkipped('symlink creation not permitted on this host');
        return;
      }

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(link.existsSync(), isTrue);
      expect(target.existsSync(), isTrue);
    });
  });

  group('sweepOrphanImportDirs — age gate', () {
    test('a freshly named orphan survives the default gate', () async {
      await seedLiveManga();
      final now = DateTime.now().millisecondsSinceEpoch;
      final fresh = plantDir('book_${now}_ab12cd34');

      expect(await repo.sweepOrphanImportDirs(), 0);
      expect(fresh.existsSync(), isTrue);
    });

    test('a future-named orphan survives even a zero gate', () async {
      await seedLiveManga();
      final future = DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch;
      final dir = plantDir('book_${future}_ab12cd34');

      expect(await repo.sweepOrphanImportDirs(minAge: Duration.zero), 0);
      expect(dir.existsSync(), isTrue);
    });

    test('an unparseable timestamp is skipped, never deleted', () async {
      await seedLiveManga();
      final dir = plantDir('book_99999999999999999999_ab12cd34');

      expect(await repo.sweepOrphanImportDirs(minAge: Duration.zero), 0);
      expect(dir.existsSync(), isTrue);
    });

    test('an orphan older than the gate is quarantined', () async {
      await seedLiveManga();
      final eightDaysAgo = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch;
      final dir = plantDir('manga_$eightDaysAgo');

      expect(await repo.sweepOrphanImportDirs(), 1);
      expect(dir.existsSync(), isFalse);
    });
  });

  group('sweepOrphanImportDirs — trash lifecycle', () {
    test('expired trash entries are hard-deleted, fresh ones kept', () async {
      await seedLiveManga();
      final trash = Directory(p.join(booksRoot.path, '.trash'))
        ..createSync(recursive: true);
      Directory(p.join(trash.path, '1000_book_1_aaaaaaaa')).createSync();
      final recentMs = DateTime.now().millisecondsSinceEpoch;
      Directory(p.join(trash.path, '${recentMs}_book_2_bbbbbbbb')).createSync();
      Directory(p.join(trash.path, 'garbage-name')).createSync();
      // Old timestamp but a suffix no quarantine could have produced —
      // the delete predicate must refuse it.
      Directory(p.join(trash.path, '1000_random_dir')).createSync();

      await repo.sweepOrphanImportDirs();

      expect(trashEntryNames()..sort(), [
        '1000_random_dir',
        '${recentMs}_book_2_bbbbbbbb',
        'garbage-name',
      ]);
    });

    test('quarantined dirs keep their contents until expiry', () async {
      await seedLiveManga();
      plantDir(ancientOrphan);

      await repo.sweepOrphanImportDirs();

      final entry = trashEntryNames().single;
      final junk = File(p.join(booksRoot.path, '.trash', entry, 'junk.bin'));
      expect(junk.existsSync(), isTrue);
    });
  });

  group('sweepOrphanImportDirs — in-flight imports', () {
    test('a registered dir survives any gate; unregistered is swept', () async {
      await seedLiveManga();
      final dir = plantDir(ancientOrphan);
      BookRepository.inFlightImportDirNames.add(ancientOrphan);

      expect(await repo.sweepOrphanImportDirs(minAge: Duration.zero), 0);
      expect(dir.existsSync(), isTrue);

      BookRepository.inFlightImportDirNames.remove(ancientOrphan);
      expect(await repo.sweepOrphanImportDirs(minAge: Duration.zero), 1);
      expect(dir.existsSync(), isFalse);
    });

    test('a failed import leaves the registry empty', () async {
      // The source file doesn't exist, so CbzParser.extract throws inside
      // the import-dir body — exercising the failure path end to end.
      final cbzPath = p.join(tempDir.path, 'missing.cbz');

      await expectLater(repo.importCbz(cbzPath), throwsA(anything));
      expect(BookRepository.inFlightImportDirNames, isEmpty);
    });

    test('a sweep racing a live import never breaks it', () async {
      await seedLiveManga();
      final archive = Archive();
      final png = img.encodePng(img.Image(width: 2, height: 2));
      archive.addFile(ArchiveFile('page_1.png', png.length, png));
      final cbzPath = p.join(tempDir.path, 'race.cbz');
      await File(cbzPath).writeAsBytes(ZipEncoder().encode(archive));

      final importing = repo.importCbz(cbzPath);
      final sweeping = repo.sweepOrphanImportDirs(minAge: Duration.zero);

      final book = await importing;
      await sweeping;

      expect(BookRepository.inFlightImportDirNames, isEmpty);
      expect(Directory(book.filePath).existsSync(), isTrue);
      expect(
        jsonDecode(
          File(p.join(book.filePath, 'pages_cache.json')).readAsStringSync(),
        ),
        isNotNull,
      );
    });
  });

  group('deleteBook hardening', () {
    test('deletes the EPUB wrapper even when content/ is gone', () async {
      final wrapper = plantDir('book_5_aaaaaaaa');
      File(p.join(wrapper.path, 'original.epub')).writeAsBytesSync([1]);
      final id = await insertEpub('book_5_aaaaaaaa');

      await repo.deleteBook(id);

      expect(wrapper.existsSync(), isFalse);
      expect(await repo.getBookById(id), isNull);
    });

    test('a malformed row can never delete the books root', () async {
      final survivor = plantDir('manga_1');
      // dirname of this filePath is the books root itself.
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'malformed',
              filePath: p.join(booksRoot.path, 'content'),
            ),
          );

      await repo.deleteBook(id);

      expect(booksRoot.existsSync(), isTrue);
      expect(survivor.existsSync(), isTrue);
      expect(await repo.getBookById(id), isNull);
    });
  });
}
