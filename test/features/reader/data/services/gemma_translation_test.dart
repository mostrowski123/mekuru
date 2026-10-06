import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mekuru/gemma');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'translate' ? '  The cat.  ' : null;
        });
  });

  test('the download size comes from the pinned file', () {
    expect(
      GemmaTranslation.downloadSize(),
      '${(gemmaModelFile.bytes / 1e9).toStringAsFixed(1)} GB',
    );
  });

  test('no app directory reads as not installed', () async {
    // Widget tests have no path_provider: status must not throw.
    expect(
      await GemmaTranslation.instance.status('en'),
      TranslationStatus.needsDownload,
    );
  });

  test('translate names the language and trims the reply', () async {
    final english = await GemmaTranslation.instance.translateWith(
      modelPath: '/models/gemma.litertlm',
      text: '猫です。',
      target: 'zh-Hans',
    );
    expect(english, 'The cat.');
    expect(calls.map((c) => c.method), ['load', 'translate']);
    expect(calls.first.arguments, {
      'path': '/models/gemma.litertlm',
      'cacheDir': '/models',
    });
    expect(calls.last.arguments, {
      'text': '猫です。',
      'language': 'Simplified Chinese',
    });
  });

  test('a CPU fallback on load is logged', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'load' ? 'cpu' : 'x',
        );
    final events = <String>[];
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        events.add(message);
    addTearDown(() => usageLogSinkOverride = null);
    await GemmaTranslation.instance.translateWith(
      modelPath: '/models/cpu.litertlm',
      text: '猫',
      target: 'en',
    );
    expect(events, ['translation.gemma_cpu']);
  });
}
