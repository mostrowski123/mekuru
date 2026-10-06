import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/mozilla_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The engines keep their folders for good, so one app directory serves
  // the whole file and is emptied between tests.
  late Directory support;

  setUpAll(() {
    support = Directory.systemTemp.createTempSync('translation_models_');
    PathProviderPlatform.instance = FakePathProviderPlatform(support.path);
  });
  tearDownAll(() => support.deleteSync(recursive: true));
  tearDown(() {
    for (final entity in support.listSync()) {
      entity.deleteSync(recursive: true);
    }
  });

  test('removing Standard keeps the Gemma model', () async {
    final standard = File(
      p.join(support.path, 'translation_models', 'ja-en', 'INSTALLED'),
    )..createSync(recursive: true);
    final gemma = File(p.join(support.path, 'gemma-4-e2b', 'INSTALLED'))
      ..createSync(recursive: true);
    expect(
      await GemmaTranslation.instance.status('en'),
      TranslationStatus.installed,
    );

    await MozillaTranslation.instance.delete();

    expect(standard.existsSync(), isFalse);
    expect(gemma.existsSync(), isTrue);
    expect(
      await GemmaTranslation.instance.status('en'),
      TranslationStatus.installed,
    );
  });
}
