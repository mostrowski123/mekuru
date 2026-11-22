import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/platform/network_status.dart';
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

import '../test_app.dart';

/// Overrides for the Downloads screen's notifiers: only the [installed]
/// dictionaries, no database, and every download start recorded in [started]
/// instead of running (`jmdict:<variant>`, `kanjidic`, `jpdb`,
/// `catalog:<entry>`, `kanjivg`, `enhanced_furigana`).
/// [jmdictDownloading] shows a JMdict download already running. [kanjiVg],
/// [enhancedFurigana] and [fixed] (where it gives one) make the notifier
/// used instead of the fake.
List<Override> fakeDownloadNotifierOverrides(
  List<String> started, {
  List<DictionaryMeta> installed = const [],
  bool jmdictDownloading = false,
  KanjiVgNotifier Function()? kanjiVg,
  EnhancedFuriganaDictNotifier Function()? enhancedFurigana,
  FixedDictionaryNotifier? Function(FixedDictionary dictionary)? fixed,
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
      () =>
          fixed?.call(dictionary) ??
          FakeFixedDictionaryNotifier(
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
    kanjiVg ?? () => _FakeKanjiVgNotifier(() => started.add('kanjivg')),
  ),
  enhancedFuriganaDictProvider.overrideWith(
    enhancedFurigana ??
        () => _FakeEnhancedFuriganaDictNotifier(
          () => started.add('enhanced_furigana'),
        ),
  ),
];

/// The Downloads screen, or [home], in Japanese, tall enough that every row
/// is built, over [container].
Future<void> pumpInJapanese(
  WidgetTester tester,
  ProviderContainer container, {
  Widget home = const DownloadsScreen(),
}) async {
  SharedPreferences.setMockInitialValues({});
  mockWifiConnected(true);
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: buildLocalizedTestApp(home: home, locale: const Locale('ja')),
    ),
  );
  await tester.pump();
}

/// Download text that is English or an exception's own, where the screen is
/// in Japanese.
final untranslatedDownloadText = find.textContaining(
  RegExp('Exception|Download failed|successfully|deleted|installed|removed'),
);

/// The real one checks a file, which never answers under a widget test's fake
/// clock, so the Downloads row would spin for ever.
class FakeWordAudio extends WordAudio {
  FakeWordAudio({this.isInstalled = false});
  final bool isInstalled;

  @override
  Future<bool> get installed async => isInstalled;
}

/// Answers the Wi-Fi check that `isOnWifi()` makes, on Android and on iOS,
/// for the rest of the test. [offline]: no network at all (`isConnected()`),
/// so not on Wi-Fi either.
void mockWifiConnected(
  bool connected, {
  bool vpn = false,
  bool offline = false,
}) {
  assert(!(connected && offline));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const iosNetwork = MethodChannel('mekuru/network');
  messenger.setMockMethodCallHandler(
    LocalMangaOcr.channel,
    (call) async => switch (call.method) {
      'isWifiConnected' => connected,
      'isNetworkConnected' => !offline,
      'isVpnActive' => vpn,
      _ => null,
    },
  );
  messenger.setMockMethodCallHandler(
    iosNetwork,
    (call) async => switch (call.method) {
      'isUnmetered' => connected,
      'isConnected' => !offline,
      _ => null,
    },
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
  Future<void> download(
    NetworkConsent network, [
    YomitanDictType? variant,
  ]) async => onDownload(variant);
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
  Future<void> download(
    NetworkConsent network, {
    bool replaceJmdict = false,
  }) async {
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
  Future<void> download(NetworkConsent network) async => onDownload();
}

class _FakeEnhancedFuriganaDictNotifier extends EnhancedFuriganaDictNotifier {
  _FakeEnhancedFuriganaDictNotifier(this.onDownload);

  final VoidCallback onDownload;

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download(NetworkConsent network) async => onDownload();
}
