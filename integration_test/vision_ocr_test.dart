import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/manga/data/services/vision_page_ocr.dart';

/// iOS only: runs the real `mekuru/vision_ocr` channel (Apple Vision) on a
/// page drawn here, so no copyrighted fixture is needed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget column(String text) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final rune in text.runes)
        Text(
          String.fromCharCode(rune),
          style: const TextStyle(
            fontSize: 40,
            height: 1.05,
            color: Colors.black,
          ),
        ),
    ],
  );

  testWidgets(
    'Apple Vision reads vertical Japanese and the lines group into one block',
    skip: !Platform.isIOS,
    (tester) async {
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
      final page = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        return recognizePageWithVision(png!.buffer.asUint8List(), 'page.png');
      });

      final text = page!.blocks.expand((b) => b.lines).join();
      // ignore: avoid_print
      print('Vision read: ${page.blocks.map((b) => b.lines).toList()}');
      expect(page.blocks, hasLength(1));
      expect(page.blocks.single.vertical, isTrue);
      expect(text, contains('天気'));
      expect(text, contains('散歩'));
    },
  );
}
