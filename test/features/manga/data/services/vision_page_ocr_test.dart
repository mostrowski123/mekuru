import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_client.dart';
import 'package:mekuru/features/manga/data/services/vision_page_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mekuru/vision_ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Vision lines become cache blocks with a quad per line', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'recognizeLines');
      return {
        'width': 1000,
        'height': 1500,
        'lines': [
          {
            'box': [100.0, 100.0, 140.0, 300.0],
            'text': '左の行',
          },
          {
            'box': [150.0, 100.0, 190.0, 300.0],
            'text': '右の行',
          },
        ],
      };
    });

    final page = await recognizePageWithVision(Uint8List(0), '0001.jpg');

    expect((page.imgWidth, page.imgHeight), (1000, 1500));
    final block = page.blocks.single;
    expect(block.vertical, isTrue);
    expect(block.box, [100.0, 100.0, 190.0, 300.0]);
    expect(block.fontSize, 40);
    expect(block.lines, ['右の行', '左の行']);
    // Clockwise from the top-left, index-aligned with `lines`.
    expect(block.linesCoords.first, [
      [150.0, 100.0],
      [190.0, 100.0],
      [190.0, 300.0],
      [150.0, 300.0],
    ]);
  });

  test('a Vision failure surfaces as the error the page loop handles', () {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'vision_failed', message: 'no image');
    });

    expect(
      recognizePageWithVision(Uint8List(0), '0001.jpg'),
      throwsA(isA<OcrServerException>()),
    );
  });
}
