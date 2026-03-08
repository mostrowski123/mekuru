import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeJmdictNotifier extends JmdictNotifier {
  _FakeJmdictNotifier(this.onDownload);

  final void Function(YomitanDictType variant) onDownload;

  @override
  JmdictState build() => const JmdictState();

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
  JpdbFreqState build() => const JpdbFreqState();

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download() async {
    onDownload();
  }
}

class _FakeKanjidicNotifier extends KanjidicNotifier {
  @override
  KanjidicState build() => const KanjidicState();

  @override
  Future<void> checkStatus() async {}
}

class _FakeKanjiVgNotifier extends KanjiVgNotifier {
  @override
  KanjiVgState build() => const KanjiVgState();

  @override
  Future<void> checkStatus() async {}
}

void main() {
  testWidgets('starter pack starts both downloads together', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final started = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jmdictProvider.overrideWith(
            () => _FakeJmdictNotifier(
              (variant) => started.add('jmdict:${variant.name}'),
            ),
          ),
          jpdbFreqProvider.overrideWith(
            () => _FakeJpdbFreqNotifier(() => started.add('jpdb')),
          ),
          kanjidicProvider.overrideWith(_FakeKanjidicNotifier.new),
          kanjiVgProvider.overrideWith(_FakeKanjiVgNotifier.new),
        ],
        child: const MaterialApp(home: DownloadsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Install Starter Pack'));
    await tester.pump();

    expect(started, unorderedEquals(<String>['jmdict:jmdictEnglish', 'jpdb']));
  });
}
