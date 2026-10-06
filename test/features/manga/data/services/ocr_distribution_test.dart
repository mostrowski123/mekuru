import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ndl_text_model.dart';
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
    expect(files.length, 4);
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
      File('$plugin/assets/licenses/MANGA-OCR.txt').readAsStringSync(),
      contains('aa6573bd10b0d446cbf622e29c3e084914df9741'),
    );
    final ndl = File(
      '$plugin/assets/licenses/NDLOCR-LITE.txt',
    ).readAsStringSync();
    expect(ndl, contains('National Diet Library'));
    expect(ndl, contains('636d1cfeb1331f89f4048f416e49e23a09a714b5'));
    expect(ndl, contains('https://creativecommons.org/licenses/by/4.0/'));
    expect(ndl, contains('without modification'));
    expect(ndl, contains('https://github.com/baudm/parseq'));
    // The notice names exactly what the app downloads.
    for (final file in ndlTextModelFiles) {
      expect(ndl, contains(file.name));
      expect(ndl, contains(file.sha256));
      expect(file.url, contains('636d1cfeb1331f89f4048f416e49e23a09a714b5'));
    }
    expect(
      File('$plugin/assets/licenses/CC-BY-4.0.txt').readAsStringSync(),
      contains('Attribution 4.0 International'),
    );
  });
  test('shipped assets do not contain weights or restricted benchmark data', () {
    final roots = [
      Directory('$plugin/assets'),
      Directory('$plugin/android/src/main/assets'),
    ];
    // The speed test's page is script-generated (tools/make_ocr_sample_page.py):
    // the only image that may ship, and it must stay small.
    final samplePage = RegExp(r'[\\/]local_manga_ocr[\\/]sample\.jpg$');
    for (final root in roots) {
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (samplePage.hasMatch(file.path)) {
          expect(file.lengthSync(), lessThan(300 * 1000));
          continue;
        }
        expect(
          file.path,
          isNot(matches(RegExp(r'\.(onnx|pt|safetensors|png|jpg|zip)$'))),
        );
        expect(file.path.toLowerCase(), isNot(contains('manga109')));
      }
    }
  });
  test('release variant excludes synthetic inference and recovery hooks', () {
    final release = File(
      '$plugin/android/src/release/kotlin/moe/matthew/mekuru/ocr/DebugOcrHooks.kt',
    ).readAsStringSync();
    expect(release, contains('const val enabled=false'));
    expect(release, isNot(contains('testEngine')));
    expect(release, isNot(contains('Thread.sleep')));
  });
}
