import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/manga/data/services/local_ocr_client.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FreeClient implements LocalOcrClient {
  final List<OcrJobSpec> started = [];
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<OcrModelState> modelState() async =>
      const OcrModelState({'supported': true, 'installed': true});
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
  late Book manga;
  late _FreeClient client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('ocr-sheet-test');
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
    await root.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester, {List<int> visible = const []}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localOcrClientProvider.overrideWithValue(client),
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
          ocrProgressProvider(1).overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showOcrActionSheet(context, manga, visiblePages: visible),
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
      expect(
        (await SharedPreferences.getInstance()).getString(
          'ocr.preferred_backend',
        ),
        'onDevice',
      );
    },
  );
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
}
