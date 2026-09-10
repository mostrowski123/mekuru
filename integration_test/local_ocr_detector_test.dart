import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:path_provider/path_provider.dart';

// Synthetic arithmetic graph, generated from constant averaging
// filters. No trained weights, images, or restricted text. Not an app asset.
const fixture =
    "CAg62AMKMwoGaW1hZ2VzCgdhdmVyYWdlEgNzZWciBENvbnYqFQoMa2VybmVsX3NoYXBlQAFAAaABBwokCgNzZWcKA3NlZxIDZGV0IgZDb25jYXQqCwoEYXhpcxgBoAECCiAKA3NlZxIGcG9vbGVkIhFHbG9iYWxBdmVyYWdlUG9vbAovCgZwb29sZWQKBWJveGVzEgFiIgRDb252KhUKDGtlcm5lbF9zaGFwZUABQAGgAQcKGAoBYgoFc2hhcGUSA2JsayIHUmVzaGFwZRISc3ludGhldGljLWRldGVjdG9yKiEIAQgDCAEIARABQgdhdmVyYWdlSgyrqqo+q6qqPquqqj4qLwgHCAEIAQgBEAFCBWJveGVzShwAAIA/AACAPwAAgD8AAIA/AACAPwAAgD8AAIA/KiUIAxAHQgVzaGFwZUoYAQAAAAAAAAABAAAAAAAAAAcAAAAAAAAAWiIKBmltYWdlcxIYChYIARISCgIIAQoCCAMKAwiACAoDCIAIYhkKA2JsaxISChAIARIMCgIIAQoCCAEKAggHYh8KA3NlZxIYChYIARISCgIIAQoCCAEKAwiACAoDCIAIYh8KA2RldBIYChYIARISCgIIAQoCCAIKAwiACAoDCIAIQgQKABAN";
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native detector transfers tensors, replaces inputs, and closes safely',
    () async {
      final root = await getApplicationSupportDirectory();
      final file = File('${root.path}/synthetic-detector.onnx');
      await file.writeAsBytes(base64Decode(fixture));
      try {
        final result = await LocalMangaOcr.channel
            .invokeMapMethod<String, dynamic>('test.detectorFixture', {
              'path': file.path,
            });
        expect(result!['closedRejected'], true);
        final passes = result['passes'] as List;
        expect(passes, hasLength(2));
        for (var i = 0; i < 2; i++) {
          final tensors = passes[i] as List;
          expect(tensors.map((t) => (t as Map)['size']), [
            7,
            1024 * 1024,
            2 * 1024 * 1024,
          ]);
          for (final t in tensors) {
            expect((t as Map)['first'], closeTo(i == 0 ? .25 : .75, .0001));
            expect(t['last'], closeTo(i == 0 ? .25 : .75, .0001));
          }
        }
      } finally {
        await file.delete();
      }
    },
  );
  test(
    'missing detector file becomes a platform error without crashing',
    () async {
      final root = await getApplicationSupportDirectory();
      await expectLater(
        LocalMangaOcr.channel.invokeMethod('test.detectorFixture', {
          'path': '${root.path}/does-not-exist.onnx',
        }),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
