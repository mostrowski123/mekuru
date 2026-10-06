import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Android's High quality engine end to end: Gemma 4 E2B (about 2.6 GB)
/// downloaded from Hugging Face and run in LiteRT-LM, then the fall back to
/// Standard when the model can't load. Local only: too big for CI. Run it
/// with `flutter drive --profile --driver=test_driver/integration_test.dart`;
/// a debug build downloads too slowly.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'downloads Gemma, translates, and falls back to Standard',
    (tester) async {
      await tester.runAsync(() async {
        final gemma = GemmaTranslation.instance;
        await gemma.delete();
        expect(await gemma.status('en'), TranslationStatus.needsDownload);

        final clock = Stopwatch()..start();
        await gemma.downloadModel();
        debugPrint('Gemma download + verify: ${clock.elapsed}');
        expect(await gemma.status('en'), TranslationStatus.installed);

        clock.reset();
        final english = await translateSentence(
          '猫が好きです。',
          'en',
          highQuality: true,
        );
        debugPrint('Gemma first load + en: ${clock.elapsed} "${english.text}"');
        expect(english.highQuality, isTrue);
        expect(english.text.toLowerCase(), contains('cat'));

        final support = await getApplicationSupportDirectory();
        final model = File(
          p.join(
            support.path,
            'translation_models',
            'gemma-4-e2b',
            gemmaModelFile.name,
          ),
        );
        // Loading the live model again is a no-op that names its backend.
        final backend = await const MethodChannel('mekuru/gemma')
            .invokeMethod<String>('load', {
              'path': model.path,
              'cacheDir': model.parent.path,
            });
        debugPrint('Gemma backend: $backend');

        clock.reset();
        final spanish = await translateSentence(
          '猫が好きです。',
          'es',
          highQuality: true,
        );
        debugPrint('Gemma es: ${clock.elapsed} "${spanish.text}"');
        expect(spanish.highQuality, isTrue);
        expect(spanish.text.toLowerCase(), contains('gato'));

        // A model that won't load falls back to Standard. The INSTALLED
        // marker stays, so Gemma is still tried first. A new sentence:
        // the last one is cached.
        await downloadTranslation('en');
        await model.rename('${model.path}.moved');
        await gemma.close();
        expect(await gemma.status('en'), TranslationStatus.installed);
        final fallback = await translateSentence(
          '犬が好きです。',
          'en',
          highQuality: true,
        );
        debugPrint('Fallback: "${fallback.text}"');
        expect(fallback.highQuality, isFalse);
        expect(fallback.text.toLowerCase(), contains('dog'));

        await gemma.delete();
        await deleteTranslation();
        expect(await gemma.status('en'), TranslationStatus.needsDownload);
      });
    },
    skip: defaultTargetPlatform != TargetPlatform.android,
    // The x86_64 emulator takes 20 minutes to over an hour for the 2.6 GB.
    timeout: const Timeout(Duration(hours: 3)),
  );
}
