import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/main.dart';
import 'package:pdfrx/pdfrx.dart' show PdfException, PdfPasswordException;
import 'package:sentry_flutter/sentry_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/epub_fixtures.dart';
import '../../../../shared/fake_path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = AppLocalizationsEn();
  late Directory tempDir;
  late AppDatabase db;
  late ProviderContainer container;
  final fixtureDirs = <String>[];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('book_import_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
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
      expect(finalState.successMessage!(en), 'Imported 2 books');

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
      expect(
        state.error!(en),
        'Imported 1 of 2.\n'
        "Couldn't import missing.epub: The file couldn't be read.",
      );
    });

    test('a single failed file says why, without a batch summary', () async {
      final empty = File('${tempDir.path}/empty.cbz')
        ..writeAsBytesSync(const []);

      await container.read(bookImportProvider.notifier).importFiles([
        empty.path,
      ], format: 'cbz');

      expect(
        container.read(bookImportProvider).error!(en),
        "Couldn't import empty.cbz: No pages or images were found.",
      );
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
        expect(state.successMessage!(en), '"吾輩は猫である" added to library!');
        expect(state.importedBook, isNotNull);
        expect(state.batchTotal, isNull);
      },
    );

    test('importOne records the source on the book it returns', () async {
      // The free-book Read action and the scanned-PDF notice hold this
      // book; OCR reads its source to pick the NDL model.
      final path = await fixtureEpub(title: '走れメロス', fileName: 'free.epub');

      final book = await container
          .read(bookImportProvider.notifier)
          .importOne(path, format: 'epub', sourceId: 'aozora:1567');

      expect(book.sourceId, 'aozora:1567');
      expect((await db.select(db.books).getSingle()).sourceId, 'aozora:1567');
    });

    test('returns 0 for an empty path list without touching state', () async {
      final imported = await container
          .read(bookImportProvider.notifier)
          .importFiles(const [], format: 'epub');

      expect(imported, 0);
      expect(container.read(bookImportProvider).isImporting, isFalse);
    });
  });

  test('importFailureReason names each kind of failure', () {
    String reason(Object error) => importFailureReason(en, error);

    expect(
      reason(const PdfPasswordException('No password supplied')),
      en.libraryImportReasonPasswordProtected,
    );
    expect(
      reason(const PdfException('Failed to load PDF document', 3)),
      en.libraryImportReasonDamaged,
    );
    expect(
      reason(const PdfException('Failed to load PDF document', 2)),
      en.libraryImportReasonUnreadable,
    );
    expect(
      reason(const FormatException('EPUB file is corrupt')),
      en.libraryImportReasonDamaged,
    );
    expect(reason(const NoPagesException()), en.libraryImportReasonNoPages);
    expect(
      reason(UnsupportedError('Unsupported file type: .txt')),
      en.libraryImportReasonUnsupported,
    );
    expect(
      reason(const PathNotFoundException('a.epub', OSError('No such file', 2))),
      en.libraryImportReasonUnreadable,
    );
    expect(
      reason(const FileSystemException('write', 'a', OSError('Full', 28))),
      en.localOcrStorageFull,
    );
    expect(reason(StateError('bug')), en.libraryImportReasonUnknown);
  });

  group('BookImportNotifier failure telemetry', () {
    late List<({String message, Map<String, SentryAttribute> attrs, bool warn})>
    logs;
    late List<({String name, Map<String, SentryAttribute>? attrs})> counts;

    setUp(() {
      logs = [];
      counts = [];
      usageLogSinkOverride = (message, attributes, {required isWarning}) =>
          logs.add((message: message, attrs: attributes, warn: isWarning));
      usageCountSinkOverride = (name, value, attributes) =>
          counts.add((name: name, attrs: attributes));
      usageAnalyticsSinkOverride = (name, parameters) {};
    });

    tearDown(() {
      usageLogSinkOverride = null;
      usageCountSinkOverride = null;
      usageAnalyticsSinkOverride = null;
    });

    test('reports a failed import as a warning, and counts it', () async {
      final missing = '${tempDir.path}/missing.epub'; // never written

      await container.read(bookImportProvider.notifier).importFiles([
        missing,
      ], format: 'epub');

      final failures = logs.where((l) => l.message == 'book.import_failed');
      expect(failures, hasLength(1));
      expect(failures.single.warn, isTrue);
      expect(failures.single.attrs['format']?.value, 'epub');
      // The exception text can embed the book file name, so only its type
      // may leave the device.
      expect(failures.single.attrs, contains('error_type'));
      expect(failures.single.attrs.containsKey('missing.epub'), isFalse);

      // Counting as well as logging is what makes a failure *rate* derivable
      // against book.imported.
      final counted = counts.where((c) => c.name == 'book.import_failed');
      expect(counted, hasLength(1));
      expect(counted.single.attrs?['format']?.value, 'epub');
    });

    test('logs nothing on the failure channel when imports succeed', () async {
      final path = await fixtureEpub(title: '坊っちゃん', fileName: 'ok.epub');

      await container.read(bookImportProvider.notifier).importFiles([
        path,
      ], format: 'epub');

      expect(logs.where((l) => l.warn), isEmpty);
      expect(counts.where((c) => c.name == 'book.import_failed'), isEmpty);
    });
  });
}
