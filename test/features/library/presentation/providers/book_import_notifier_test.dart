import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/main.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/epub_fixtures.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late ProviderContainer container;
  final fixtureDirs = <String>[];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('book_import_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    // Cancel the success banner auto-dismiss timer before disposal.
    container.read(bookImportProvider.notifier).clearState();
    container.dispose();
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    for (final dir in fixtureDirs) {
      try {
        Directory(dir).deleteSync(recursive: true);
      } catch (_) {
        // Windows can hold locks on temp files; OS cleans them up.
      }
    }
    fixtureDirs.clear();
  });

  Future<String> fixtureEpub({
    required String title,
    required String fileName,
  }) async {
    final path = await createTestEpub(title: title, fileName: fileName);
    fixtureDirs.add(File(path).parent.path);
    return path;
  }

  group('BookImportNotifier.importFiles', () {
    test('imports multiple EPUBs and reports a batch summary', () async {
      final paths = [
        await fixtureEpub(title: '坊っちゃん', fileName: 'botchan.epub'),
        await fixtureEpub(title: '走れメロス', fileName: 'melos.epub'),
      ];

      final states = <BookImportState>[];
      container.listen(bookImportProvider, (_, next) => states.add(next));

      final imported = await container
          .read(bookImportProvider.notifier)
          .importFiles(paths, format: 'epub');

      expect(imported, 2);

      final books = await db.select(db.books).get();
      expect(books, hasLength(2));
      expect(books.map((b) => b.title), containsAll(['坊っちゃん', '走れメロス']));

      final finalState = container.read(bookImportProvider);
      expect(finalState.isImporting, isFalse);
      expect(finalState.successMessage, 'Imported 2 books');

      final batchSteps = states
          .where((s) => s.batchTotal != null)
          .map((s) => (s.batchCurrent, s.batchTotal))
          .toSet();
      expect(batchSteps, containsAll([(1, 2), (2, 2)]));
    });

    test('continues past a failing file and summarizes the failure', () async {
      final good = await fixtureEpub(title: '坊っちゃん', fileName: 'good.epub');
      final missing = '${tempDir.path}/missing.epub'; // never written

      final imported = await container
          .read(bookImportProvider.notifier)
          .importFiles([missing, good], format: 'epub');

      expect(imported, 1);

      final books = await db.select(db.books).get();
      expect(books, hasLength(1));
      expect(books.single.title, '坊っちゃん');

      final state = container.read(bookImportProvider);
      expect(state.isImporting, isFalse);
      expect(state.error, contains('Imported 1 of 2'));
      expect(state.error, contains('missing.epub'));
    });

    test(
      'single file keeps the per-book success message and Open Now book',
      () async {
        final path = await fixtureEpub(title: '吾輩は猫である', fileName: 'neko.epub');

        final imported = await container
            .read(bookImportProvider.notifier)
            .importFiles([path], format: 'epub');

        expect(imported, 1);

        final state = container.read(bookImportProvider);
        expect(state.successMessage, '"吾輩は猫である" added to library!');
        expect(state.importedBook, isNotNull);
        expect(state.batchTotal, isNull);
      },
    );

    test('returns 0 for an empty path list without touching state', () async {
      final imported = await container
          .read(bookImportProvider.notifier)
          .importFiles(const [], format: 'epub');

      expect(imported, 0);
      expect(container.read(bookImportProvider).isImporting, isFalse);
    });
  });
}
