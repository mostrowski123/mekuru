import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ndl_text_model.dart';
import 'package:mekuru/features/manga/data/services/vision_page_ocr.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_path_provider.dart';

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

  test('a Vision failure is a recognition error, not a server one', () {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'vision_failed', message: 'no image');
    });

    expect(
      recognizePageWithVision(Uint8List(0), '0001.jpg'),
      throwsA(isA<TextRecognitionException>()),
    );
  });

  group('NDL reads the long lines', () {
    late Directory root;
    late String ndlDir;
    // A vertical block: the right line is too long for manga-ocr.
    const longVision = 'ビジョンの長い行の読みは間違っている';
    const shortVision = '短い行';
    // Class i + 1 is the charset's i-th character: 長い行を読むA and a space.
    final charsetYaml = 'model:\n  charset_train: "長い行を読むA "\n';

    setUp(() {
      root = Directory.systemTemp.createTempSync('ndl_ocr_test');
      // No manga-ocr pack installed under it.
      PathProviderPlatform.instance = FakePathProviderPlatform(root.path);
      ndlDir = p.join(root.path, 'ndl_text_model');
      File(p.join(ndlDir, 'NDLmoji.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(charsetYaml);
    });
    tearDown(() => root.deleteSync(recursive: true));

    /// `[1, steps, classes]` logits whose best class per step is [best],
    /// then the end token.
    Map<String, Object> ndlReply(List<int> best) {
      const steps = 10, classes = 9;
      final logits = Float32List(steps * classes);
      for (var step = 0; step < steps; step++) {
        logits[step * classes + (step < best.length ? best[step] : 0)] = 1;
      }
      return {'logits': logits, 'steps': steps, 'classes': classes};
    }

    Future<(List<String>, List<String>)> scan(
      Object? Function() ndlRun, {
      bool withNdl = true,
    }) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'recognizeLines':
            return {
              'width': 200,
              'height': 400,
              'lines': [
                {
                  'box': [100.0, 100.0, 140.0, 300.0],
                  'text': shortVision,
                },
                {
                  'box': [150.0, 100.0, 190.0, 300.0],
                  'text': longVision,
                },
              ],
            };
          case 'decodeRgba':
            return {
              'width': 200,
              'height': 400,
              'rgba': Uint8List(200 * 400 * 4),
            };
          case 'ndlLoad':
            expect(
              call.arguments,
              p.join(ndlDir, ndlTextModelFiles.first.name),
            );
            return true;
          case 'ndlRun':
            expect((call.arguments as Float32List).length, 3 * 24 * 768);
            return ndlRun();
        }
        fail('unexpected ${call.method}');
      });
      final page = await recognizePageWithVision(
        Uint8List(0),
        '0001.png',
        ndlModelDir: withNdl ? ndlDir : null,
      );
      return (page.blocks.single.lines, calls);
    }

    test('a long line gets NDL\'s text, a short one keeps Vision\'s', () async {
      final (lines, calls) = await scan(
        () => ndlReply([1, 2, 3, 4, 5, 6, 8, 7]),
      );
      // Cleaned like manga-ocr's text: no whitespace, ASCII full width.
      expect(lines, ['長い行を読むＡ', shortVision]);
      // Without the manga-ocr pack, only the long line is read.
      expect(calls, ['recognizeLines', 'decodeRgba', 'ndlLoad', 'ndlRun']);
    });

    test('without an NDL model nothing changes', () async {
      final (lines, calls) = await scan(() => fail('NDL ran'), withNdl: false);
      expect(lines, [longVision, shortVision]);
      expect(calls, ['recognizeLines']);
    });

    test('a failed or empty NDL reading keeps Vision\'s text', () async {
      final (failed, _) = await scan(
        () => throw PlatformException(code: 'ndl_failed'),
      );
      expect(failed, [longVision, shortVision]);
      for (final best in [
        <int>[],
        [8],
      ]) {
        final (empty, _) = await scan(() => ndlReply(best));
        expect(empty, [longVision, shortVision]);
      }
    });
  });
}
