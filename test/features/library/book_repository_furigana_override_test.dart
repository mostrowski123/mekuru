import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';

AppDatabase _createDb() => AppDatabase(NativeDatabase.memory());

Future<int> _insertBook(AppDatabase db, {String title = 'Test'}) async {
  return db
      .into(db.books)
      .insert(BooksCompanion.insert(title: title, filePath: '/fake/$title'));
}

void main() {
  late AppDatabase db;
  late BookRepository repo;

  setUp(() {
    db = _createDb();
    repo = BookRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('BookRepository.updateDisplayOverrides — furiganaMode', () {
    test('newly imported book has null furiganaMode override', () async {
      final id = await _insertBook(db);
      final book = (await repo.getBookById(id))!;
      expect(book.furiganaMode, isNull);
    });

    test('writing Value("all") persists the column', () async {
      final id = await _insertBook(db);
      await repo.updateDisplayOverrides(
        id,
        verticalText: null,
        readingDirection: null,
        furiganaMode: const Value('all'),
      );
      final book = (await repo.getBookById(id))!;
      expect(book.furiganaMode, 'all');
    });

    test('Value.absent() leaves furiganaMode unchanged', () async {
      final id = await _insertBook(db);
      await repo.updateDisplayOverrides(
        id,
        verticalText: null,
        readingDirection: null,
        furiganaMode: const Value('all'),
      );

      // Now update only verticalText with furiganaMode absent — must not
      // clobber the previously stored 'all'.
      await repo.updateDisplayOverrides(
        id,
        verticalText: true,
        readingDirection: null,
      );

      final book = (await repo.getBookById(id))!;
      expect(book.furiganaMode, 'all');
      expect(book.overrideVerticalText, isTrue);
    });

    test('Value(null) clears furiganaMode', () async {
      final id = await _insertBook(db);
      await repo.updateDisplayOverrides(
        id,
        verticalText: null,
        readingDirection: null,
        furiganaMode: const Value('aboveLevel'),
      );
      await repo.updateDisplayOverrides(
        id,
        verticalText: null,
        readingDirection: null,
        furiganaMode: const Value(null),
      );
      final book = (await repo.getBookById(id))!;
      expect(book.furiganaMode, isNull);
    });

    test('per-book values are independent', () async {
      final aId = await _insertBook(db, title: 'A');
      final bId = await _insertBook(db, title: 'B');

      await repo.updateDisplayOverrides(
        aId,
        verticalText: null,
        readingDirection: null,
        furiganaMode: const Value('all'),
      );
      await repo.updateDisplayOverrides(
        bId,
        verticalText: null,
        readingDirection: null,
        furiganaMode: const Value('off'),
      );

      final a = (await repo.getBookById(aId))!;
      final b = (await repo.getBookById(bId))!;
      expect(a.furiganaMode, 'all');
      expect(b.furiganaMode, 'off');
    });
  });
}
