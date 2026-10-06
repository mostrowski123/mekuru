import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';

class _Engine implements TranslationEngine {
  _Engine(this.name);
  final String name;
  TranslationStatus state = TranslationStatus.installed;
  bool fails = false;
  int calls = 0;
  @override
  Future<TranslationStatus> status(String target) async => state;
  @override
  Future<void> download(String target) async {}
  @override
  Future<String> translate(String text, String target) async {
    calls++;
    if (fails) throw StateError('$name failed');
    return '$name:$text';
  }
}

void main() {
  late _Engine standard;
  late _Engine high;
  setUp(() {
    standard = _Engine('std');
    high = _Engine('gemma');
    debugTranslationEngine = standard;
    debugHighQualityEngine = high;
  });
  tearDown(() {
    debugTranslationEngine = null;
    debugHighQualityEngine = null;
  });

  test('High quality uses Gemma once installed', () async {
    final r = await translateSentence('猫1', 'en', highQuality: true);
    expect(r, (text: 'gemma:猫1', highQuality: true));
  });

  test('High quality not downloaded yet translates with Standard', () async {
    high.state = TranslationStatus.needsDownload;
    final r = await translateSentence('猫2', 'en', highQuality: true);
    expect(r, (text: 'std:猫2', highQuality: false));
  });

  test('a Gemma failure falls back to Standard for that sentence', () async {
    high.fails = true;
    final r = await translateSentence('猫3', 'en', highQuality: true);
    expect(r, (text: 'std:猫3', highQuality: false));
  });

  test('Standard choice never touches Gemma', () async {
    await translateSentence('猫4', 'en');
    expect(high.calls, 0);
  });

  test('status: installed when either engine can serve', () async {
    standard.state = TranslationStatus.needsDownload;
    expect(
      await translationStatus('en', highQuality: true),
      TranslationStatus.installed,
    );
    expect(await translationStatus('en'), TranslationStatus.needsDownload);
  });

  test('Gemma failing with no Standard model surfaces the error', () async {
    high.fails = true;
    standard.fails = true;
    expect(translateSentence('猫5', 'en', highQuality: true), throwsStateError);
  });
}
