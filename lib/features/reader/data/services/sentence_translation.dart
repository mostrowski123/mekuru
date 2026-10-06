import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
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

/// Replaces Gemma in tests.
@visibleForTesting
TranslationEngine? debugHighQualityEngine;

/// Gemma when the user chose High quality on Android, else null.
TranslationEngine? _highQualityEngine(bool highQuality) {
  if (!highQuality) return null;
  if (debugHighQualityEngine case final engine?) return engine;
  return defaultTargetPlatform == TargetPlatform.android
      ? GemmaTranslation.instance
      : null;
}

/// Installed when the chosen engine, or Standard as its fallback, can
/// translate now.
Future<TranslationStatus> translationStatus(
  String target, {
  bool highQuality = false,
}) async {
  final high = _highQualityEngine(highQuality);
  if (high != null &&
      await high.status(target) == TranslationStatus.installed) {
    return TranslationStatus.installed;
  }
  return _engine.status(target);
}

/// The Standard engine's download (Gemma's goes through its notifier).
Future<void> downloadTranslation(String target) => _engine.download(target);

/// Android only: iOS language packs belong to the system.
Future<void> deleteTranslation() => MozillaTranslation.instance.delete();

/// What Android downloads for [target], for the mobile-data question.
String translationDownloadSize(String target) =>
    MozillaTranslation.downloadSize(target);

/// A translation and whether High quality (Gemma) produced it.
typedef SentenceTranslation = ({String text, bool highQuality});

// The Sentence tab, another word of the same sentence and the Anki button
// all ask for the latest sentence, so one entry is the whole cache.
((String, String, bool), Future<SentenceTranslation>)? _lastTranslation;

/// Translates [text] into [target] with Gemma when [highQuality] and it is
/// ready, else Standard. A Gemma failure falls back to Standard for this
/// sentence. Shares the latest result; a failure is not kept, nor a
/// Standard fallback for High quality, so Gemma takes over once ready.
Future<SentenceTranslation> translateSentence(
  String text,
  String target, {
  bool highQuality = false,
}) {
  final wantsHigh = _highQualityEngine(highQuality) != null;
  final key = (text, target, wantsHigh);
  final last = _lastTranslation;
  if (last != null && last.$1 == key) return last.$2;
  final translation = _translate(text, target, highQuality);
  _lastTranslation = (key, translation);
  translation.then<void>(
    (r) {
      if (wantsHigh &&
          !r.highQuality &&
          identical(_lastTranslation?.$2, translation)) {
        _lastTranslation = null;
      }
    },
    onError: (Object _) {
      if (identical(_lastTranslation?.$2, translation)) _lastTranslation = null;
    },
  );
  return translation;
}

Future<SentenceTranslation> _translate(
  String text,
  String target,
  bool highQuality,
) async {
  final high = _highQualityEngine(highQuality);
  if (high != null &&
      await high.status(target) == TranslationStatus.installed) {
    // Standard's WebView would hold its memory while Gemma loads, unless a
    // Standard translation still runs in it. Only the real engine: tests'
    // fakes have nothing to stop.
    if (_engine case final MozillaTranslation standard when !standard.isBusy) {
      try {
        await standard.stop();
      } catch (e) {
        // Gemma, or Standard as its fallback, still translates.
        logFailure('translation.standard_stop_failed', e);
      }
    }
    try {
      return (text: await high.translate(text, target), highQuality: true);
    } catch (e) {
      logFailure('translation.high_quality_failed', e);
    }
  }
  return (text: await _engine.translate(text, target), highQuality: false);
}

/// [sentence] in [target] when an engine is ready, else null: for callers
/// like the Anki button that must not stall or ask to download.
Future<String?> translateIfInstalled(
  String sentence,
  String target, {
  bool highQuality = false,
}) async {
  try {
    if (await translationStatus(target, highQuality: highQuality) !=
        TranslationStatus.installed) {
      return null;
    }
    final result = await translateSentence(
      sentence,
      target,
      highQuality: highQuality,
    ).timeout(const Duration(seconds: 15));
    return result.text;
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
