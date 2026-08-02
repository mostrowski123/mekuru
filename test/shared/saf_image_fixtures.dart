import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1x1 transparent PNG.
const List<int> kTransparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const safChannel = MethodChannel('mekuru/android_saf');

/// Clears the image cache and stubs SAF tree reads to return
/// [kTransparentPng], recording each read's relative path in the returned
/// list. Call from `setUp`, and pair with [clearSafImageStub] in `tearDown`.
List<String> stubSafImageReads() {
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  final readPaths = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(safChannel, (call) async {
        if (call.method == 'readBytesFromTreePath') {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          readPaths.add(args['relativePath']! as String);
          return Uint8List.fromList(kTransparentPng);
        }
        return null;
      });
  return readPaths;
}

void clearSafImageStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(safChannel, null);
}

/// Pumps real-async frames until [condition] holds, failing after ~500ms.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String description = 'condition',
}) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 50; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
    fail('Timed out waiting for $description');
  });
}

/// Pumps until a [RawImage] in the tree has decoded pixels.
Future<void> pumpUntilPainted(WidgetTester tester) => pumpUntil(
  tester,
  () =>
      tester.widgetList<RawImage>(find.byType(RawImage)).firstOrNull?.image !=
      null,
  description: 'an image to paint',
);
