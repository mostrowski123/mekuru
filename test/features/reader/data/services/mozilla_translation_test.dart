import 'dart:async';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/mozilla_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';

void main() {
  test('the app language picks the target, English otherwise', () {
    expect(translationTargetFor(const Locale('en')), 'en');
    expect(translationTargetFor(const Locale('es')), 'es');
    expect(translationTargetFor(const Locale('id')), 'id');
    expect(
      translationTargetFor(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ),
      'zh-Hans',
    );
    expect(translationTargetFor(const Locale('fr')), 'en');
  });

  test('Japanese pivots through English for every other target', () {
    expect(mozillaPairsFor('en'), ['ja-en']);
    expect(mozillaPairsFor('es'), ['ja-en', 'en-es']);
    expect(mozillaPairsFor('id'), ['ja-en', 'en-id']);
    expect(mozillaPairsFor('zh-Hans'), ['ja-en', 'en-zh']);
  });

  test('every target has models with the files the engine loads', () {
    for (final target in ['en', 'es', 'id', 'zh-Hans']) {
      for (final pair in mozillaPairsFor(target)) {
        final kinds = mozillaTranslationModels[pair]!
            .map((file) => file.name.split('.').first)
            .toSet();
        expect(kinds, containsAll(['model', 'lex']), reason: pair);
        expect(
          kinds.contains('vocab') ||
              kinds.containsAll(['srcvocab', 'trgvocab']),
          isTrue,
          reason: pair,
        );
      }
    }
  });

  test('a translation keeps the engine busy until it ends', () async {
    final engine = MozillaTranslation.instance;
    addTearDown(engine.stop);
    final translation = engine.translate('猫', 'en');
    expect(engine.isBusy, isTrue);
    // A test has no app directory, so the engine fails to start.
    await expectLater(translation, throwsA(anything));
    expect(engine.isBusy, isFalse);
  });

  test('stopping the engine fails a translation still running', () async {
    final engine = MozillaTranslation.instance;
    // A WebView that is still starting: the translation waits on it.
    engine.debugStart = () => Completer<InAppWebViewController>().future;
    addTearDown(() => engine.debugStart = null);
    final translation = expectLater(
      engine.translate('猫', 'en'),
      throwsA(predicate((e) => '$e'.contains('Translation engine stopped'))),
    );
    // As removing the models does.
    await engine.stop();
    await translation;
    expect(engine.isBusy, isFalse);
  });

  test('the download size counts every pair a target needs', () {
    expect(MozillaTranslation.downloadSize('en'), '55 MB');
    expect(MozillaTranslation.downloadSize('es'), '91 MB');
  });
}
