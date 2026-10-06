import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
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

  test('a partial Gemma download counts as files to remove', () async {
    expect(await GemmaTranslation.instance.hasFiles(), isFalse);
    File(
      p.join(support.path, 'gemma-4-e2b', '${gemmaModelFile.name}.part'),
    ).createSync(recursive: true);
    expect(await GemmaTranslation.instance.hasFiles(), isTrue);

    await GemmaTranslation.instance.delete();

    expect(await GemmaTranslation.instance.hasFiles(), isFalse);
  });

  test('a Gemma download cancelled before its job is queued stops', () async {
    final gemma = GemmaTranslation.instance;
    final download = gemma.downloadModel();
    expect(gemma.cancelDownload(), isTrue);

    // Here a queued job would throw: there is no WorkManager.
    await expectLater(download, throwsA(isA<HttpException>()));
  });

  test('a Gemma download without room for the model and its cache fails '
      'before fetching', () async {
    const saf = MethodChannel('mekuru/android_saf');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      saf,
      (call) async => call.method == 'getFreeBytes' ? 1000000000 : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(saf, null));
    File(p.join(support.path, 'gemma-4-e2b', '${gemmaModelFile.name}.part'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(1000, 0));

    await expectLater(
      GemmaTranslation.instance.downloadModel(),
      throwsA(
        isA<InsufficientSpaceException>().having(
          (e) => e.neededBytes,
          'neededBytes',
          // The rest of the model, plus LiteRT-LM's weight cache.
          gemmaModelFile.bytes - 1000 + 800000000 - 1000000000,
        ),
      ),
    );
  });
}
