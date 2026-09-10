import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/data/services/local_ocr_client.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_page_overlay.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'reader opens OCR options on first tap and immediately shows cancellable scan',
    (tester) async {
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
      final client = _NativeTestClient();
      await tester.pumpWidget(
        buildIntegrationTestApp(
          db: db,
          home: MangaReaderScreen(book: book),
          extraOverrides: [localOcrClientProvider.overrideWithValue(client)],
        ),
      );
      // A center tap exposes the toolbar if reader controls start hidden.
      await tester.pump(const Duration(seconds: 2));
      if (find.byTooltip(l.localOcrRecognize).evaluate().isEmpty) {
        await tester.tapAt(tester.getCenter(find.byType(MangaReaderScreen)));
      }
      await pumpUntilVisible(tester, find.byTooltip(l.localOcrRecognize));
      await tester.tap(find.byTooltip(l.localOcrRecognize));
      await pumpUntilVisible(tester, find.byType(OcrActionSheet));
      await pumpUntilVisible(tester, find.text(l.localOcrThisPage(page: 8)));
      // The private reproduction archive contains previous OCR; replace it.
      if (supplied.isNotEmpty) {
        await tester.tap(find.text(l.localOcrReplace));
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.ensureVisible(find.text(l.localOcrStartPages(count: 1)));
      await tester.tap(find.text(l.localOcrStartPages(count: 1)));
      await pumpUntilGone(tester, find.byType(OcrActionSheet));
      await pumpUntilVisible(
        tester,
        find.descendant(
          of: find.byType(LocalOcrPageOverlay),
          matching: find.text(l.commonCancel),
        ),
      );
      expect(find.byType(MangaReaderScreen), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(LocalOcrPageOverlay),
          matching: find.text(l.commonCancel),
        ),
      );
      await pumpUntilGone(
        tester,
        find.descendant(
          of: find.byType(LocalOcrPageOverlay),
          matching: find.text(l.commonCancel),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await LocalMangaOcr.quiesce();
      await db.close();
      await root.delete(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
