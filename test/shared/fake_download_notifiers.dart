import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';

/// Overrides for the Downloads screen's notifiers: only the [installed]
/// dictionaries, no database, and every download start recorded in [started]
/// instead of running (`jmdict:<variant>`, `jpdb`, `catalog:<entry>`).
/// [jmdictDownloading] shows a JMdict download already running.
List<Override> fakeDownloadNotifierOverrides(
  List<String> started, {
  List<DictionaryMeta> installed = const [],
  bool jmdictDownloading = false,
}) => [
  dictionariesProvider.overrideWith((ref) => Stream.value(installed)),
  for (final entry in CatalogDictionary.values)
    catalogDownloadProvider(entry).overrideWith(
      () => FakeCatalogDownloadNotifier(
        entry,
        (entry) => started.add('catalog:${entry.name}'),
      ),
    ),
  jmdictProvider.overrideWith(
    () => _FakeJmdictNotifier(
      (v) => started.add('jmdict:${v.name}'),
      JmdictState(isDownloading: jmdictDownloading),
    ),
  ),
  jpdbFreqProvider.overrideWith(
    () => _FakeJpdbFreqNotifier(() => started.add('jpdb')),
  ),
  kanjidicProvider.overrideWith(_FakeKanjidicNotifier.new),
  kanjiVgProvider.overrideWith(_FakeKanjiVgNotifier.new),
];

/// Answers the Wi-Fi check that `isOnWifi()` makes, on Android and on iOS,
/// for the rest of the test.
void mockWifiConnected(bool connected) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const iosNetwork = MethodChannel('mekuru/network');
  messenger.setMockMethodCallHandler(
    LocalMangaOcr.channel,
    (call) async => call.method == 'isWifiConnected' ? connected : null,
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

class _FakeJmdictNotifier extends JmdictNotifier {
  _FakeJmdictNotifier(this.onDownload, this.initial);

  final void Function(YomitanDictType variant) onDownload;
  final JmdictState initial;

  @override
  JmdictState build() => initial;

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download(YomitanDictType variant) async {
    onDownload(variant);
  }
}

class _FakeJpdbFreqNotifier extends JpdbFreqNotifier {
  _FakeJpdbFreqNotifier(this.onDownload);

  final VoidCallback onDownload;

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download() async {
    onDownload();
  }
}

/// Records [download] calls instead of downloading, then shows [result];
/// [delete] calls go to [onDelete].
class FakeCatalogDownloadNotifier extends CatalogDownloadNotifier {
  FakeCatalogDownloadNotifier(
    super.entry,
    this.onDownload, {
    this.result = const CatalogDownloadState(),
    this.onDelete,
  });

  final void Function(CatalogDictionary entry) onDownload;
  final CatalogDownloadState result;
  final void Function(int dictionaryId)? onDelete;

  @override
  Future<void> download() async {
    onDownload(entry);
    state = result;
  }

  @override
  Future<void> delete(int dictionaryId) async => onDelete?.call(dictionaryId);
}

class _FakeKanjidicNotifier extends KanjidicNotifier {
  @override
  Future<void> checkStatus() async {}
}

class _FakeKanjiVgNotifier extends KanjiVgNotifier {
  @override
  Future<void> checkStatus() async {}
}
