import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_ios.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/data/services/vision_block_grouping.dart';
import 'package:mekuru/features/manga/data/services/vision_page_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// iOS only: runs the real `mekuru/vision_ocr` channel (Apple Vision) on a
/// page drawn here, so no copyrighted fixture is needed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget column(String text, {double size = 40}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final rune in text.runes)
        Text(
          String.fromCharCode(rune),
          style: TextStyle(fontSize: size, height: 1.05, color: Colors.black),
        ),
    ],
  );

  /// Pumps a white page with two vertical columns and returns it as a PNG.
  Future<({List<int> png, int width, int height})> drawPage(
    WidgetTester tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(48),
                // Vertical text reads right to left.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    column('今日は天気がいい'),
                    const SizedBox(width: 14),
                    column('散歩に行きましょう'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return (
        png: png!.buffer.asUint8List().toList(),
        width: image.width,
        height: image.height,
      );
    }))!;
  }

  /// Pumps a white landscape page: a column at each edge and one centred on
  /// the gutter. Wider than tall, so `visionPasses` in AppDelegate.swift reads
  /// it as two overlapping passes. It has to fit the device: a SizedBox wider
  /// than the screen is constrained down and anything positioned past the
  /// screen edge is never drawn.
  Future<({List<int> png, int width, int height})> drawSpread(
    WidgetTester tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                width: 360,
                height: 230,
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      top: 16,
                      child: column('今日は天気', size: 36),
                    ),
                    // Centred, so it stays on the gutter whatever width the
                    // device gives us, and inside both passes' overlap.
                    Positioned.fill(
                      top: 16,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: column('散歩に行く', size: 36),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      top: 16,
                      child: column('読書します', size: 36),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return (
        png: png!.buffer.asUint8List().toList(),
        width: image.width,
        height: image.height,
      );
    }))!;
  }

  testWidgets(
    'a landscape spread is read as two passes, in page coordinates',
    skip: !Platform.isIOS,
    (tester) async {
      final drawn = await drawSpread(tester);
      expect(
        drawn.width,
        greaterThan(drawn.height),
        reason: 'the page has to be landscape for visionPasses to split it',
      );
      final page = await tester.runAsync(
        () => recognizePageWithVision(
          Uint8List.fromList(drawn.png),
          'spread.png',
        ),
      );

      // ignore: avoid_print
      print(
        'spread blocks: '
        '${page!.blocks.map((b) => (b.lines, b.box)).toList()}',
      );
      // Blocks read right to left, so the first is the right-hand column.
      expect(page.blocks, hasLength(3));
      // The right-hand column is found by the second pass only. Its box has
      // to carry that pass's offset: without it the box lands near x = 0.
      expect(
        page.blocks.first.box[0],
        greaterThan(drawn.width / 2),
        reason: 'the second pass box was not mapped back onto the page',
      );
      expect(page.blocks.last.box[2], lessThan(drawn.width / 2));
      // The column on the gutter is inside both passes; it is kept once, so
      // its block holds one line and not the same line twice.
      final gutter = page.blocks.firstWhere(
        (b) => b.box[0] < drawn.width / 2 && b.box[2] > drawn.width / 2,
        orElse: () => throw StateError('nothing was found on the gutter'),
      );
      expect(
        gutter.lines,
        hasLength(1),
        reason: 'a line on the seam came back from both passes',
      );
      expect(page.blocks.expand((b) => b.lines).join(), contains('天気'));
    },
  );

  testWidgets(
    'Apple Vision reads vertical Japanese and the lines group into one block',
    skip: !Platform.isIOS,
    (tester) async {
      final drawn = await drawPage(tester);
      final page = await tester.runAsync(
        () =>
            recognizePageWithVision(Uint8List.fromList(drawn.png), 'page.png'),
      );

      final text = page!.blocks.expand((b) => b.lines).join();
      // ignore: avoid_print
      print('Vision read: ${page.blocks.map((b) => b.lines).toList()}');
      expect(page.blocks, hasLength(1));
      expect(page.blocks.single.vertical, isTrue);
      expect(text, contains('天気'));
      expect(text, contains('散歩'));
    },
  );

  testWidgets(
    'manga-ocr reads the block Vision found, through ONNX Runtime',
    skip: !Platform.isIOS,
    timeout: const Timeout(Duration(minutes: 20)),
    (tester) async {
      final drawn = await drawPage(tester);
      final bytes = Uint8List.fromList(drawn.png);
      final readings = await tester.runAsync(() async {
        // About 200 MB from Hugging Face the first time on a simulator.
        if (!await MangaOcrIos.instance.installed) {
          await MangaOcrIos.instance.download();
        }
        final page = await recognizePageWithVision(bytes, 'page.png');
        final direct = await MangaOcrIos.instance.readBlocks(bytes, [
          VisionBlock(
            vertical: true,
            lines: [
              VisionLine(
                left: 0,
                top: 0,
                right: drawn.width.toDouble(),
                bottom: drawn.height.toDouble(),
                text: 'x',
              ),
            ],
          ),
        ]);
        return (page: page.blocks.single.lines, direct: direct);
      });

      // ignore: avoid_print
      print(
        'manga-ocr read: ${readings!.page} / whole page: ${readings.direct}',
      );
      // Not null: the model ran, this is not the Vision fallback.
      expect(readings.direct, isNotNull);
      expect(readings.page, ['今日は天気がいい', '散歩に行きましょう']);
    },
  );

  testWidgets(
    'an on-device scan writes Vision blocks and their words into the cache',
    skip: !Platform.isIOS,
    (tester) async {
      final drawn = await drawPage(tester);
      final root = await tester.runAsync(
        () async => Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'vision_it_${DateTime.now().microsecondsSinceEpoch}',
          ),
        ).create(),
      );
      addTearDown(() => root!.delete(recursive: true));
      final bookId = DateTime.now().millisecondsSinceEpoch % 2000000000;
      final cache = File(p.join(root!.path, 'pages_cache.json'));

      final progress = await tester.runAsync(() async {
        await File(p.join(root.path, '0.png')).writeAsBytes(drawn.png);
        await cache.writeAsString(
          jsonEncode({
            'title': 'Vision integration test',
            'imageDirPath': root.path,
            'ocrCompleted': false,
            'pages': [
              {
                'pageIndex': 0,
                'imageFileName': '0.png',
                'imgWidth': drawn.width,
                'imgHeight': drawn.height,
                'blocks': <Object>[],
              },
            ],
          }),
        );
        await scheduleOcrTask(
          bookId: bookId,
          cacheFilePath: cache.path,
          imageDir: root.path,
          onDevice: true,
        );
        final prefs = await SharedPreferences.getInstance();
        OcrProgress? progress;
        for (var i = 0; i < 120; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await prefs.reload();
          progress = OcrProgress.load(prefs, bookId);
          if (progress?.status == OcrStatus.completed ||
              progress?.status == OcrStatus.failed) {
            break;
          }
        }
        return progress;
      });

      expect(
        progress?.status,
        OcrStatus.completed,
        reason: '${progress?.errorMessage}',
      );
      final saved =
          jsonDecode(cache.readAsStringSync()) as Map<String, dynamic>;
      final page = (saved['pages'] as List).single as Map<String, dynamic>;
      final block = (page['blocks'] as List).single as Map<String, dynamic>;
      // ignore: avoid_print
      print(
        'cache block: ${block['lines']} words: ${(block['words'] as List?)?.length}',
      );
      expect(saved['ocrSource'], 'on_device');
      expect((page['ocr'] as Map)['source'], 'vision');
      expect(block['vertical'], isTrue);
      expect((block['lines'] as List).join(), contains('天気'));
      // Word tapping needs the MeCab segmentation the page loop adds.
      expect(block['words'], isNotEmpty);
    },
  );
}
