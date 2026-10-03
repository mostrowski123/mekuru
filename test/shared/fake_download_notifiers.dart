import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
