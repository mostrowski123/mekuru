import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';

/// Android's Sentence tab engine end to end: Mozilla's models downloaded from
/// Mozilla's CDN, the WebAssembly engine in a headless WebView, and a pivot
/// through English. Needs the network for about 90 MB of models.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'downloads the models and translates Japanese',
    (tester) async {
      await tester.runAsync(() async {
        await deleteTranslation();
        expect(await translationStatus('en'), TranslationStatus.needsDownload);

        await downloadTranslation('en');
        expect(await translationStatus('en'), TranslationStatus.installed);
        expect(await translationStatus('es'), TranslationStatus.needsDownload);

        expect((await translateSentence('今日はいい天気ですね。', 'en')).text, isNotEmpty);
        final english = (await translateSentence('猫が好きです。', 'en')).text;
        expect(english.toLowerCase(), contains('cat'));

        await downloadTranslation('es');
        final spanish = (await translateSentence('猫が好きです。', 'es')).text;
        expect(spanish.toLowerCase(), contains('gato'));

        await deleteTranslation();
        expect(await translationStatus('en'), TranslationStatus.needsDownload);
      });
    },
    skip: defaultTargetPlatform != TargetPlatform.android,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
