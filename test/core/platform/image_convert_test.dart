import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/image_convert.dart';

import '../../shared/avif_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mekuru/image_convert');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<ui.Codec> engineFails() async => throw Exception('Invalid image data');

  test('decodes AVIF the engine cannot read on the platform side', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'decodeRgba');
      return {'width': 2, 'height': 3, 'rgba': Uint8List(2 * 3 * 4)};
    });

    final codec = await decodeWithAvifFallback(avifHeader(), engineFails);
    final image = (await codec.getNextFrame()).image;
    expect([image.width, image.height], [2, 3]);
  });

  test('scales the platform decode down to the target width only', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'width': 4, 'height': 6, 'rgba': Uint8List(4 * 6 * 4)},
    );

    Future<int> widthFor(int target) async {
      final codec = await decodeWithAvifFallback(
        avifHeader(),
        engineFails,
        targetWidth: target,
      );
      return (await codec.getNextFrame()).image.width;
    }

    expect(await widthFor(2), 2);
    expect(await widthFor(8), 4);
  });

  test('rethrows engine failures for anything but AVIF', () async {
    var asked = false;
    messenger.setMockMethodCallHandler(channel, (_) async => asked = true);

    await expectLater(
      decodeWithAvifFallback(Uint8List.fromList([1, 2, 3]), engineFails),
      throwsException,
    );
    expect(asked, isFalse);
  });

  test('fails when the platform cannot read the AVIF either', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    await expectLater(
      decodeWithAvifFallback(avifHeader(), engineFails),
      throwsStateError,
    );
  });
}
