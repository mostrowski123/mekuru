import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/features/reader/data/services/mozilla_translation.dart';

/// On-device Japanese translation for the lookup sheet's Sentence tab:
/// Mozilla's Firefox Translations engine on Android, Apple's Translation
/// framework on iOS. Failures surface as exceptions; callers show them.

enum TranslationStatus { installed, needsDownload, unsupported }

/// One platform's translation engine.
abstract interface class TranslationEngine {
  Future<TranslationStatus> status(String target);

  /// Gets what [target] needs. On iOS this shows Apple's own prompt, which
  /// the user may decline: check [status] afterwards.
  Future<void> download(String target);

  Future<String> translate(String text, String target);
}

/// Replaces the platform's engine in tests.
@visibleForTesting
TranslationEngine? debugTranslationEngine;

TranslationEngine get _engine =>
    debugTranslationEngine ??
    (defaultTargetPlatform == TargetPlatform.iOS
        ? const _AppleTranslation()
        : MozillaTranslation.instance);

/// The translation target for the app's effective UI [locale].
String translationTargetFor(Locale locale) => switch (locale.languageCode) {
  'es' => 'es',
  'id' => 'id',
  'zh' => 'zh-Hans',
  _ => 'en',
};

Future<TranslationStatus> translationStatus(String target) =>
    _engine.status(target);

Future<void> downloadTranslation(String target) => _engine.download(target);

/// Android only: iOS language packs belong to the system.
Future<void> deleteTranslation() => MozillaTranslation.instance.delete();

/// What Android downloads for [target], for the mobile-data question.
String translationDownloadSize(String target) =>
    MozillaTranslation.downloadSize(target);

// The Sentence tab, another word of the same sentence and the Anki button
// all ask for the latest sentence, so one entry is the whole cache.
((String, String), Future<String>)? _lastTranslation;

/// Translates [text] into [target], sharing the latest result (and a
/// request in flight). A failure is not kept, so a retry asks again.
Future<String> translateSentence(String text, String target) {
  final key = (text, target);
  final last = _lastTranslation;
  if (last != null && last.$1 == key) return last.$2;
  final translation = _engine.translate(text, target);
  _lastTranslation = (key, translation);
  translation.then<void>(
    (_) {},
    onError: (Object _) {
      if (identical(_lastTranslation?.$2, translation)) _lastTranslation = null;
    },
  );
  return translation;
}

/// [sentence] in [target] when the engine is already installed, else null:
/// for callers like the Anki button that must not stall or ask to download.
Future<String?> translateIfInstalled(String sentence, String target) async {
  try {
    if (await translationStatus(target) != TranslationStatus.installed) {
      return null;
    }
    return await translateSentence(
      sentence,
      target,
    ).timeout(const Duration(seconds: 5));
  } catch (_) {
    return null;
  }
}

/// Apple's Translation framework behind `mekuru/translation`
/// (`TranslationBridge` in AppDelegate.swift).
class _AppleTranslation implements TranslationEngine {
  const _AppleTranslation();

  static const _channel = MethodChannel('mekuru/translation');

  @override
  Future<TranslationStatus> status(String target) async {
    try {
      final status = await _channel.invokeMethod<String>('status', {
        'target': target,
      });
      return TranslationStatus.values.asNameMap()[status] ??
          TranslationStatus.unsupported;
    } on MissingPluginException {
      return TranslationStatus.unsupported;
    }
  }

  @override
  Future<void> download(String target) =>
      _channel.invokeMethod<void>('download', {'target': target});

  @override
  Future<String> translate(String text, String target) async =>
      await _channel.invokeMethod<String>('translate', {
        'text': text,
        'target': target,
      }) ??
      '';
}
