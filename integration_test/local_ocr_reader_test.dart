import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/local_ocr_client.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/manga/presentation/services/ocr_purchase_flow.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_page_overlay.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

class _NativeTestClient implements LocalOcrClient {
  OcrJobProgress? created;
  @override
  Future<OcrModelState> modelState() async =>
      const OcrModelState({'supported': true, 'installed': true});
  @override
  Future<bool> requestNotifications() async => true;
  @override
  Future<void> cancel(String jobId) => LocalMangaOcr.cancel(jobId);
  @override
  Future<OcrJobProgress> start(OcrJobSpec spec) async {
    // Synthetic inference only; service, store, callbacks, and reader are real.
    final result = await LocalMangaOcr.channel.invokeMapMethod<String, dynamic>(
      'start',
      {...spec.toJson(), 'testEngine': true, 'testDelaySteps': 300},
    );
    return created = OcrJobProgress(Map<String, dynamic>.from(result!));
  }
}

/// A reader opened on page 8 of a 12-page fixture (or `OCR_REPRO_CBZ`), with
/// the toolbar revealed.
class _Reader {
  final AppLocalizations l;
  final _NativeTestClient client = _NativeTestClient();
  final bool supplied;
  final Directory _root;
  final AppDatabase _db;
  late final Book book;
  _Reader._(this.l, this.supplied, this._root, this._db);

  static Future<_Reader> open(
    WidgetTester tester, {
    List<Override> Function(Book book)? overrides,
  }) async {
    final db = createTestDatabase();
    final root = await Directory.systemTemp.createTemp('ocr-reader-');
    final repository = BookRepository(db);
    final l = await loadExpectedL10n();
    final supplied = const String.fromEnvironment('OCR_REPRO_CBZ');
    var source = supplied;
    if (source.isEmpty) {
      final page = img.Image(width: 300, height: 500);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));
      final bytes = img.encodePng(page);
      final archive = Archive();
      for (var index = 0; index < 12; index++) {
        archive.addFile(
          ArchiveFile(
            "${index.toString().padLeft(4, '0')}.png",
            bytes.length,
            bytes,
          ),
        );
      }
      source = "${root.path}/fixture.cbz";
      await File(source).writeAsBytes(ZipEncoder().encode(archive));
    }
    final imported = await repository.importCbz(source);
    final book = imported.copyWith(lastReadCfi: const Value('7'));
    final reader = _Reader._(l, supplied.isNotEmpty, root, db)..book = book;
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: MangaReaderScreen(book: book),
        extraOverrides: [
          localOcrClientProvider.overrideWithValue(reader.client),
          ...?overrides?.call(book),
        ],
      ),
    );
    // A center tap exposes the toolbar if reader controls start hidden.
    await tester.pump(const Duration(seconds: 2));
    if (find.byTooltip(l.localOcrRecognizeQuick).evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(MangaReaderScreen)));
    }
    await pumpUntilVisible(tester, find.byTooltip(l.localOcrRecognizeQuick));
    return reader;
  }

  Finder get button => find.byTooltip(l.localOcrRecognizeQuick);

  Finder get overlayCancel => find.descendant(
    of: find.byType(LocalOcrPageOverlay),
    matching: find.text(l.commonCancel),
  );

  Future<void> cancelScan(WidgetTester tester) async {
    await pumpUntilVisible(tester, overlayCancel);
    expect(find.byType(MangaReaderScreen), findsOneWidget);
    await tester.tap(overlayCancel);
    await pumpUntilGone(tester, overlayCancel);
  }

  Future<void> close(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    await LocalMangaOcr.quiesce();
    await _db.close();
    await _root.delete(recursive: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late OcrPurchaseFlow originalFlow;
  var unlocked = true;
  var proOpens = 0;
  setUp(() async {
    unlocked = true;
    proOpens = 0;
    // A tap only scans once an engine has been chosen; without one it opens
    // the sheet (covered below).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ocrPreferredBackendKey, OcrBackend.onDevice.name);
    // The shared integration app pins proUnlockedProvider to locked; the OCR
    // gate reads Pro through this seam instead.
    originalFlow = OcrPurchaseFlow.instance;
    OcrPurchaseFlow.instance = OcrPurchaseFlow(
      readProUnlocked: () async => unlocked,
      openProUpgradeScreen: (_) async {
        proOpens++;
      },
    );
  });
  tearDown(() => OcrPurchaseFlow.instance = originalFlow);

  testWidgets('holding the OCR button opens the options sheet, which starts a '
      'cancellable scan', (tester) async {
    final reader = await _Reader.open(tester);
    final l = reader.l;
    await tester.longPress(reader.button);
    await pumpUntilVisible(tester, find.byType(OcrActionSheet));
    await pumpUntilVisible(tester, find.text(l.localOcrThisPage(page: 8)));
    // The private reproduction archive contains previous OCR; replace it.
    if (reader.supplied) {
      await tester.tap(find.text(l.localOcrReplace));
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.ensureVisible(find.text(l.localOcrStartPages(count: 1)));
    await tester.tap(find.text(l.localOcrStartPages(count: 1)));
    await pumpUntilGone(tester, find.byType(OcrActionSheet));
    await reader.cancelScan(tester);
    await reader.close(tester);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets(
    'tapping the OCR button scans the visible page without a sheet',
    (tester) async {
      final reader = await _Reader.open(tester);
      await tester.tap(reader.button);
      await pumpUntilVisible(tester, reader.overlayCancel);
      expect(find.byType(OcrActionSheet), findsNothing);
      if (!reader.supplied) expect(reader.client.created?.json['pages'], [7]);
      // The receipt names the engine and is the tappable way to the options.
      expect(
        find.text(reader.l.localOcrQuickStartedOnDevice(count: 1, pages: '8')),
        findsOneWidget,
      );
      await tester.tap(find.text(reader.l.localOcrOptions));
      await pumpUntilVisible(tester, find.byType(OcrActionSheet));
      Navigator.of(tester.element(find.byType(OcrActionSheet))).pop();
      await pumpUntilGone(tester, find.byType(OcrActionSheet));
      await reader.cancelScan(tester);
      await reader.close(tester);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'the first tap, before any engine was chosen, opens the options sheet',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(ocrPreferredBackendKey);
      final reader = await _Reader.open(tester);
      await tester.tap(reader.button);
      await pumpUntilVisible(tester, find.byType(OcrActionSheet));
      expect(reader.client.created, isNull);
      expect(reader.overlayCancel, findsNothing);
      await reader.close(tester);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'remote OCR progress reloads the open page and reports a failed scan',
    (tester) async {
      // The remote worker reports only through ocrProgressProvider; a fake
      // stream stands in for it, and the cache edit for the page it committed.
      final progress = StreamController<OcrProgress?>();
      final reader = await _Reader.open(
        tester,
        overrides: (book) => [
          ocrProgressProvider(book.id).overrideWith((ref) => progress.stream),
        ],
      );
      final l = reader.l;
      OcrProgress at(String status, int completed, [String? error]) =>
          OcrProgress(
            completed: completed,
            total: 12,
            status: status,
            errorMessage: error,
          );
      progress.add(at(OcrStatus.running, 0));
      await tester.pump(const Duration(milliseconds: 300));

      final cache = File('${reader.book.filePath}/pages_cache.json');
      final json = jsonDecode(await cache.readAsString()) as Map;
      ((json['pages'] as List)[7] as Map)['ocr'] = {
        'completed': true,
        'source': 'remote',
      };
      await cache.writeAsString(jsonEncode(json));
      progress.add(at(OcrStatus.completed, 12));
      await pumpUntilVisible(tester, find.text(l.ocrComplete));
      // Only a reloaded page 8 knows it has OCR now.
      await tester.tap(reader.button);
      await pumpUntilVisible(tester, find.text(l.localOcrAlreadyDone));
      expect(reader.client.created, isNull);

      progress.add(at(OcrStatus.running, 0));
      await tester.pump(const Duration(milliseconds: 300));
      progress.add(at(OcrStatus.failed, 0, 'Could not connect to OCR server.'));
      await pumpUntilVisible(
        tester,
        find.text('Could not connect to OCR server.'),
      );
      // Let the bar finish sliding in; its action is off screen until then.
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(l.localOcrOptions));
      await pumpUntilVisible(tester, find.byType(OcrActionSheet));
      await progress.close();
      await reader.close(tester);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'tapping the OCR button without Pro opens the Pro screen and starts nothing',
    (tester) async {
      unlocked = false;
      final reader = await _Reader.open(tester);
      await tester.tap(reader.button);
      await tester.pump(const Duration(seconds: 2));
      expect(proOpens, 1);
      expect(reader.client.created, isNull);
      expect(find.byType(OcrActionSheet), findsNothing);
      expect(reader.overlayCancel, findsNothing);
      // Earlier cases leave cancelled jobs in the journal; none may be live.
      expect((await LocalMangaOcr.jobs()).where((j) => j.isActive), isEmpty);
      await reader.close(tester);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
