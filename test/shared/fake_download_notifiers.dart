import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/presentation/providers/word_audio_providers.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/enhanced_furigana_dict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';

/// Overrides for the Downloads screen's notifiers: only the [installed]
/// dictionaries, no database, and every download start recorded in [started]
/// instead of running (`jmdict:<variant>`, `kanjidic`, `jpdb`,
/// `catalog:<entry>`, `kanjivg`, `enhanced_furigana`).
/// [jmdictDownloading] shows a JMdict download already running.
List<Override> fakeDownloadNotifierOverrides(
  List<String> started, {
  List<DictionaryMeta> installed = const [],
  bool jmdictDownloading = false,
}) => [
  dictionariesProvider.overrideWith((ref) => Stream.value(installed)),
  wordAudioProvider.overrideWithValue(FakeWordAudio()),
  for (final entry in CatalogDictionary.values)
    catalogDownloadProvider(entry).overrideWith(
      () => FakeCatalogDownloadNotifier(
        entry,
        (entry) => started.add('catalog:${entry.name}'),
      ),
    ),
  for (final dictionary in FixedDictionary.values)
    fixedDictionaryProvider(dictionary).overrideWith(
      () => FakeFixedDictionaryNotifier(
        dictionary,
        (v) => started.add(
          v == null ? dictionary.name : '${dictionary.name}:${v.name}',
        ),
        initial: FixedDictionaryState(
          isDownloading:
              jmdictDownloading && dictionary == FixedDictionary.jmdict,
        ),
      ),
    ),
  kanjiVgProvider.overrideWith(
    () => _FakeKanjiVgNotifier(() => started.add('kanjivg')),
  ),
  enhancedFuriganaDictProvider.overrideWith(
    () => _FakeEnhancedFuriganaDictNotifier(
      () => started.add('enhanced_furigana'),
    ),
  ),
];

/// The real one checks a file, which never answers under a widget test's fake
/// clock, so the Downloads row would spin for ever.
class FakeWordAudio extends WordAudio {
  FakeWordAudio({this.isInstalled = false});
  final bool isInstalled;

  @override
  Future<bool> get installed async => isInstalled;
}

/// Answers the Wi-Fi check that `isOnWifi()` makes, on Android and on iOS,
/// for the rest of the test.
void mockWifiConnected(bool connected, {bool vpn = false}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const iosNetwork = MethodChannel('mekuru/network');
  messenger.setMockMethodCallHandler(
    LocalMangaOcr.channel,
    (call) async => switch (call.method) {
      'isWifiConnected' => connected,
      'isVpnActive' => vpn,
      _ => null,
    },
  );
  messenger.setMockMethodCallHandler(
    iosNetwork,
    (call) async => call.method == 'isUnmetered' ? connected : null,
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(LocalMangaOcr.channel, null);
    messenger.setMockMethodCallHandler(iosNetwork, null);
  });
}

/// Shows [initial] and records [download] calls instead of downloading.
class FakeFixedDictionaryNotifier extends FixedDictionaryNotifier {
  FakeFixedDictionaryNotifier(
    super.dictionary,
    this.onDownload, {
    this.initial = const FixedDictionaryState(),
  });

  final void Function(YomitanDictType? variant) onDownload;
  final FixedDictionaryState initial;

  @override
  FixedDictionaryState build() => initial;

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download([YomitanDictType? variant]) async =>
      onDownload(variant);
}

/// Records [download] calls instead of downloading, then shows [result];
/// [delete] calls go to [onDelete], downloads replacing JMdict also to
/// [onReplaceJmdict].
class FakeCatalogDownloadNotifier extends CatalogDownloadNotifier {
  FakeCatalogDownloadNotifier(
    super.entry,
    this.onDownload, {
    this.result = const CatalogDownloadState(),
    this.onDelete,
    this.onReplaceJmdict,
  });

  final void Function(CatalogDictionary entry) onDownload;
  final CatalogDownloadState result;
  final void Function(int dictionaryId)? onDelete;
  final void Function(CatalogDictionary entry)? onReplaceJmdict;

  @override
  Future<void> download({bool replaceJmdict = false}) async {
    onDownload(entry);
    if (replaceJmdict) onReplaceJmdict?.call(entry);
    state = result;
  }

  @override
  Future<void> delete(int dictionaryId) async {
    onDelete?.call(dictionaryId);
    state = CatalogDownloadState(deletedId: dictionaryId);
  }
}

class _FakeKanjiVgNotifier extends KanjiVgNotifier {
  _FakeKanjiVgNotifier(this.onDownload);

  final VoidCallback onDownload;

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download() async => onDownload();
}

class _FakeEnhancedFuriganaDictNotifier extends EnhancedFuriganaDictNotifier {
  _FakeEnhancedFuriganaDictNotifier(this.onDownload);

  final VoidCallback onDownload;

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download() async => onDownload();
}
