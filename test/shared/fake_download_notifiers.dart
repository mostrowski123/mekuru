import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';

/// Overrides for the Downloads screen's notifiers: nothing installed, no
/// database, and every download start recorded in [started] instead of
/// running (`jmdict:<variant>`, `jpdb`).
List<Override> fakeDownloadNotifierOverrides(List<String> started) => [
  jmdictProvider.overrideWith(
    () => _FakeJmdictNotifier((v) => started.add('jmdict:${v.name}')),
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
  _FakeJmdictNotifier(this.onDownload);

  final void Function(YomitanDictType variant) onDownload;

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

class _FakeKanjidicNotifier extends KanjidicNotifier {
  @override
  Future<void> checkStatus() async {}
}

class _FakeKanjiVgNotifier extends KanjiVgNotifier {
  @override
  Future<void> checkStatus() async {}
}

/// Records [update] calls instead of downloading.
class FakeUpdateNotifier extends DictionaryUpdateNotifier {
  FakeUpdateNotifier(super.dictionaryId, this.onUpdate);

  final void Function(int dictionaryId) onUpdate;

  @override
  Future<void> update() async => onUpdate(dictionaryId);
}
