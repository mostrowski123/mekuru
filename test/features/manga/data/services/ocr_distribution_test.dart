import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/widgets/ocr_attributions.dart';

void main() {
  const plugin = 'packages/local_manga_ocr';
  test('manifest pins every model artifact and exact total size', () {
    final manifest =
        jsonDecode(
              File(
                '$plugin/android/src/main/assets/local_manga_ocr/manifest.json',
              ).readAsStringSync(),
            )
            as Map;
    final files = manifest['files'] as List;
    expect(files.length, 5);
    var total = 0;
    for (final file in files.cast<Map>()) {
      expect(file['url'], startsWith('https://'));
      expect(file['url'], isNot(contains('/main/')));
      expect(file['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(file['license'], isNotEmpty);
      expect(file['bytes'], greaterThan(0));
      total += file['bytes'] as int;
    }
    expect(manifest['totalBytes'], total);
    expect(manifest['runtime'], 'onnxruntime-android:1.24.3');
  });
  test('all attribution documents exist offline and include provenance', () {
    for (final name in OcrAttributions.licenseFiles) {
      final file = File('$plugin/assets/licenses/$name');
      expect(file.existsSync(), true, reason: name);
      expect(file.lengthSync(), greaterThan(100), reason: name);
    }
    final detector = File(
      '$plugin/assets/licenses/COMIC-TEXT-DETECTOR.txt',
    ).readAsStringSync();
    expect(detector, contains('293ae8060b08f2ed323693019f9bd0c173af4eab'));
    expect(detector, contains('Modified'));
    expect(detector, contains('Corresponding source'));
    expect(
      File('$plugin/assets/licenses/BABERU.txt').readAsStringSync(),
      contains('d9cc13153e9a1cd8fdfa3b7b1cc329da2020aeae'),
    );
  });
  test(
    'shipped assets do not contain weights or restricted benchmark data',
    () {
      final roots = [
        Directory('$plugin/assets'),
        Directory('$plugin/android/src/main/assets'),
      ];
      for (final root in roots) {
        for (final file in root.listSync(recursive: true).whereType<File>()) {
          expect(
            file.path,
            isNot(matches(RegExp(r'\.(onnx|pt|safetensors|png|jpg|zip)$'))),
          );
          expect(file.path.toLowerCase(), isNot(contains('manga109')));
        }
      }
    },
  );
  test('release variant excludes synthetic inference and recovery hooks', () {
    final release = File(
      '$plugin/android/src/release/kotlin/moe/matthew/mekuru/ocr/DebugOcrHooks.kt',
    ).readAsStringSync();
    expect(release, contains('const val enabled=false'));
    expect(release, isNot(contains('testEngine')));
    expect(release, isNot(contains('Thread.sleep')));
  });
}
