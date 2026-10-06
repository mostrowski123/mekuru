import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/manga/data/services/local_ocr_client.dart';
import 'package:mekuru/features/manga/data/services/ndl_text_model.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/services/ocr_purchase_flow.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/test_database.dart';

class _FreeClient implements LocalOcrClient {
  final List<OcrJobSpec> started = [];
  var installed = true;
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<OcrModelState> modelState() async =>
      OcrModelState({'supported': true, 'installed': installed});
  @override
  Future<bool> requestNotifications() async => false;
  @override
  Future<OcrJobProgress> start(OcrJobSpec spec) async {
    started.add(spec);
    return OcrJobProgress({
      'id': 'fake',
      'bookId': spec.bookId,
      'status': 'queued',
      'pages': spec.pages,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase db;
  late _RecordingRepository repository;
  late Book manga;
  late _FreeClient client;
  late OcrPurchaseFlow originalFlow;
  late PathProviderPlatform originalPaths;
  // Page-loop scans (iOS) as startOcr scheduled them.
  late List<({bool onDevice, String? ndlModelDir})> scheduled;
  var unlocked = true;
  var proOpens = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    unlocked = true;
    proOpens = 0;
    originalFlow = OcrPurchaseFlow.instance;
    OcrPurchaseFlow.instance = OcrPurchaseFlow(
      readProUnlocked: () async => unlocked,
      openProUpgradeScreen: (_) async {
        proOpens++;
      },
    );
    root = await Directory.systemTemp.createTemp('ocr-sheet-test');
    // The NDL text model lives under app support (iOS) or next to it in
    // no_backup (Android), so both stay inside root.
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(
      p.join(root.path, 'support'),
    );
    scheduled = [];
    db = createTestDatabase();
    repository = _RecordingRepository(db);
    manga = Book(
      id: 1,
      title: 'Test manga',
      filePath: root.path,
      bookType: 'manga',
      totalPages: 3,
      readProgress: 0,
      dateAdded: DateTime(2026),
    );
    await File.fromUri(root.uri.resolve('pages_cache.json')).writeAsString(
      jsonEncode({
        'title': manga.title,
        'imageDirPath': root.path,
        'ocrCompleted': false,
        'pages': [
          for (var i = 0; i < 3; i++)
            {
              'pageIndex': i,
              'imageFileName': '$i.png',
              'imgWidth': 100,
              'imgHeight': 120,
              'blocks': [],
              if (i == 0) 'ocr': {'completed': true, 'source': 'onDevice'},
            },
        ],
      }),
    );
    client = _FreeClient();
  });
  tearDown(() async {
    await db.close();
    OcrPurchaseFlow.instance = originalFlow;
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    List<int> visible = const [],
    OcrProgress? progress,
    Book? book,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Every run first backs up the text the book came with.
          bookRepositoryProvider.overrideWithValue(repository),
          localOcrClientProvider.overrideWithValue(client),
          ocrTaskSchedulerProvider.overrideWithValue(({
            required bookId,
            required cacheFilePath,
            required imageDir,
            selectedPages,
            replace = false,
            onDevice = false,
            ndlModelDir,
          }) async {
            scheduled.add((onDevice: onDevice, ndlModelDir: ndlModelDir));
          }),
          ocrBookLoaderProvider.overrideWithValue(
            (_) async => MokuroBook(
              title: 'Test manga',
              imageDirPath: root.path,
              pages: [
                for (var i = 0; i < 3; i++)
                  MokuroPage(
                    pageIndex: i,
                    imageFileName: '$i.png',
                    imgWidth: 100,
                    imgHeight: 120,
                    blocks: const [],
                    ocr: i == 0
                        ? {'completed': true, 'source': 'onDevice'}
                        : null,
                  ),
              ],
            ),
          ),
          localOcrJobsProvider.overrideWith((ref) => Stream.value(const [])),
          // DownloadsScreen.initState calls checkStatus() on the asset
          // notifiers, which touches the file system; the fakes keep it idle
          // when startOcr pushes it.
          ...fakeDownloadNotifierOverrides(<String>[]),
          ocrProgressProvider(1).overrideWith((ref) => Stream.value(progress)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showOcrActionSheet(
                  context,
                  book ?? manga,
                  visiblePages: visible,
                ),
                child: const Text('Open OCR'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open OCR'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  // The sheet shows an indeterminate progress bar while startOcr waits on the
  // dialog, so the dialog is pumped by hand instead of pumpAndSettle.
  Future<void> openModelsMissingDialog(WidgetTester tester) async {
    client.installed = false;
    await open(tester);
    await tester.tap(find.text('Recognize 2 pages'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'free whole-manga action selects only missing pages without Pro or account',
    (tester) async {
      await open(tester);
      expect(find.text('1 of 3 pages already have OCR'), findsOneWidget);
      expect(find.text('Recognize 2 pages'), findsOneWidget);
      await tester.tap(find.text('Recognize 2 pages'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(client.started.single.pages, [1, 2]);
      expect(client.started.single.policy, OcrExistingPolicy.missingOnly);
      // Not a scanned free book: no text model, and no question about it.
      expect(client.started.single.ndlModelDir, isNull);
      // Even a run that only fills missing pages backs up the book's own
      // text first, so Delete OCR can restore it.
      expect(repository.backedUp, [manga.id]);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'ocr.preferred_backend',
        ),
        'onDevice',
      );
    },
  );
  testWidgets('a running page-loop scan is headed by the backend running it', (
    tester,
  ) async {
    const running = OcrProgress(
      completed: 1,
      total: 3,
      status: OcrStatus.running,
    );
    await open(tester, progress: running);
    expect(find.text('Remote'), findsOneWidget);

    // On iOS the page loop also runs on-device scans (the default backend).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const SizedBox());
      await open(tester, progress: running);
      expect(find.text('On device'), findsOneWidget);
      expect(find.text('Remote'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  testWidgets('spread action identifies the individual source page', (
    tester,
  ) async {
    await open(tester, visible: [1, 2]);
    expect(find.text('Page 2'), findsOneWidget);
    await tester.tap(find.text('Recognize 1 page'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(client.started.single.pages, [1]);
  });
  testWidgets('existing remote preference is retained', (tester) async {
    SharedPreferences.setMockInitialValues({'ocr.preferred_backend': 'remote'});
    await open(tester);
    final segmented = tester.widget<SegmentedButton<OcrBackend>>(
      find.byType(SegmentedButton<OcrBackend>),
    );
    expect(segmented.selected, {OcrBackend.remote});
    expect(client.started, isEmpty);
  });
  testWidgets('locked users see the Pro screen and the sheet stays open', (
    tester,
  ) async {
    unlocked = false;
    await open(tester);
    await tester.tap(find.text('Recognize 2 pages'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(proOpens, 1);
    expect(client.started, isEmpty);
    expect(find.byType(OcrActionSheet), findsOneWidget);
  });
  testWidgets('missing models explain the download; Cancel keeps the sheet', (
    tester,
  ) async {
    await openModelsMissingDialog(tester);
    expect(
      find.text(
        'On-device OCR needs its models downloaded first. Open Downloads to '
        'get them, then come back and tap OCR again.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.started, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(OcrActionSheet), findsOneWidget);
    expect(find.byType(DownloadsScreen), findsNothing);
  });
  testWidgets('missing models open Downloads on confirm', (tester) async {
    await openModelsMissingDialog(tester);
    await tester.tap(find.text('Open Downloads'));
    // startOcr keeps awaiting until Downloads is popped, so the sheet stays
    // busy underneath; pump the route transition by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DownloadsScreen), findsOneWidget);
    expect(client.started, isEmpty);
  });
  group('NDL text model', () {
    // A graded reader downloaded from Free books (a scanned PDF).
    Book tadoku() => manga.copyWith(sourceId: const Value('tadoku:42'));
    const prompt = 'Use the scanned-book reader?';

    Future<String> installModel(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final dir = await NdlTextModel.instance.path;
          // downloadModelFiles' marker of a finished download.
          await File(p.join(dir, 'INSTALLED')).create(recursive: true);
          return dir;
        }))!;

    // The sheet's progress bar runs while startOcr waits, so frames are
    // pumped by hand; the model check is real file I/O.
    Future<void> tapStart(WidgetTester tester) async {
      await tester.tap(find.text('Recognize 2 pages'));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));
    }

    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    testWidgets('missing: asks, and Scan without it starts without it', (
      tester,
    ) async {
      await open(tester, book: tadoku());
      await tapStart(tester);
      expect(find.text(prompt), findsOneWidget);
      expect(
        find.text(
          'This free book is scanned pages of text. On-device OCR reads them '
          'much better with the scanned-book reader, an optional 42.6 MB '
          'download in Downloads.',
        ),
        findsOneWidget,
      );
      expect(client.started, isEmpty);

      await tester.tap(inDialog('Scan without it'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(client.started.single.pages, [1, 2]);
      expect(client.started.single.ndlModelDir, isNull);
      expect(find.byType(OcrActionSheet), findsNothing);
    });

    testWidgets('missing: dismissing the question cancels the scan', (
      tester,
    ) async {
      await open(tester, book: tadoku());
      await tapStart(tester);
      expect(find.text(prompt), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing);
      expect(client.started, isEmpty);
      expect(find.byType(OcrActionSheet), findsOneWidget);
    });

    testWidgets('missing: Open Downloads goes there without scanning', (
      tester,
    ) async {
      await open(tester, book: tadoku());
      await tapStart(tester);
      await tester.tap(inDialog('Open Downloads'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(client.started, isEmpty);
    });

    testWidgets('installed: the job reads with it, without asking', (
      tester,
    ) async {
      final dir = await installModel(tester);
      await open(tester, book: tadoku());
      await tapStart(tester);
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing);
      expect(client.started.single.ndlModelDir, dir);
    });

    // The platform override must be undone inside the test body.
    void testIos(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets('on iOS, $name', (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          try {
            await body(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });

    testIos('missing: Scan without it runs Vision without it', (tester) async {
      await open(tester, book: tadoku());
      await tapStart(tester);
      expect(find.text(prompt), findsOneWidget);
      await tester.tap(inDialog('Scan without it'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(scheduled, [(onDevice: true, ndlModelDir: null)]);
    });

    testIos('installed: Vision scans read with it, without asking', (
      tester,
    ) async {
      final dir = await installModel(tester);
      await open(tester, book: tadoku());
      await tapStart(tester);
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing);
      expect(scheduled, [(onDevice: true, ndlModelDir: dir)]);
    });

    testIos('other books neither ask nor use it', (tester) async {
      await installModel(tester);
      await open(tester);
      await tapStart(tester);
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing);
      expect(scheduled, [(onDevice: true, ndlModelDir: null)]);
    });
  });
  group('preferredOcrBackend', () {
    MokuroBook manga({String? source, String? pageSource}) =>
        MokuroBook.fromJson({
          'title': 'Test manga',
          'imageDirPath': '/test',
          'ocrSource': ?source,
          'pages': [
            {
              'pageIndex': 0,
              'imageFileName': '0.png',
              'imgWidth': 1,
              'imgHeight': 1,
              'blocks': <Object>[],
              if (pageSource != null)
                'ocr': {'completed': true, 'source': pageSource},
            },
          ],
        });
    test('defaults to on-device', () async {
      expect(await preferredOcrBackend(manga()), OcrBackend.onDevice);
    });
    test('an explicit choice wins over history', () async {
      SharedPreferences.setMockInitialValues({
        'ocr.preferred_backend': 'remote',
      });
      expect(await preferredOcrBackend(manga()), OcrBackend.remote);
      SharedPreferences.setMockInitialValues({
        'ocr.preferred_backend': 'onDevice',
      });
      expect(
        await preferredOcrBackend(manga(pageSource: 'remote')),
        OcrBackend.onDevice,
      );
    });
    test('remote history wins when nothing was chosen', () async {
      expect(
        await preferredOcrBackend(manga(source: 'custom_ocr')),
        OcrBackend.remote,
      );
      expect(
        await preferredOcrBackend(manga(pageSource: 'remote')),
        OcrBackend.remote,
      );
      SharedPreferences.setMockInitialValues({'${ocrProgressKeyPrefix}1': '1'});
      expect(await preferredOcrBackend(manga()), OcrBackend.remote);
    });
    test('remote history is not a remembered choice', () async {
      // The reader's one-tap scan keys off this: history alone must open the
      // sheet, not send a page to a server the user never picked.
      SharedPreferences.setMockInitialValues({'${ocrProgressKeyPrefix}1': '1'});
      expect(await rememberedOcrBackend(), isNull);
      SharedPreferences.setMockInitialValues({
        'ocr.preferred_backend': 'remote',
      });
      expect(await rememberedOcrBackend(), OcrBackend.remote);
      SharedPreferences.setMockInitialValues({
        'ocr.preferred_backend': 'onDevice',
      });
      expect(await rememberedOcrBackend(), OcrBackend.onDevice);
    });
  });
}

/// Records which books were backed up instead of touching their files.
class _RecordingRepository extends BookRepository {
  _RecordingRepository(super.db);

  final backedUp = <int>[];

  @override
  Future<void> backupOriginalMokuroOcrIfNeeded(Book book) async =>
      backedUp.add(book.id);
}
