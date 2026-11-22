import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/enhanced_furigana_dict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/features/settings/presentation/widgets/jmdict_download_tile.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download_tile_state.dart';

import '../../shared/fake_download_notifiers.dart';

/// What a tile is in for a pin: installed, downloading or deleting.
typedef _Given = ({bool installed, bool downloading, bool deleting});

const _idle = (installed: false, downloading: false, deleting: false);
const _installed = (installed: true, downloading: false, deleting: false);

class _Fixed extends FixedDictionaryNotifier {
  _Fixed(super.dictionary, this.given, this.calls);

  final _Given given;
  final List<String> calls;

  @override
  DownloadTileState build() => DownloadTileState(
    isInstalled: given.installed,
    isDownloading: given.downloading,
    isDeleting: given.deleting,
  );

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download(
    NetworkConsent network, [
    YomitanDictType? variant,
  ]) async => calls.add('download ${dictionary.name}');

  @override
  Future<void> delete() async => calls.add('delete ${dictionary.name}');
}

class _KanjiVg extends KanjiVgNotifier {
  _KanjiVg(this.given, this.calls);

  final _Given given;
  final List<String> calls;

  @override
  DownloadTileState build() => DownloadTileState(
    isInstalled: given.installed,
    isDownloading: given.downloading,
    isDeleting: given.deleting,
    fileCount: given.installed ? 11661 : 0,
  );

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download(NetworkConsent network) async =>
      calls.add('download kanjivg');

  @override
  Future<void> delete() async => calls.add('delete kanjivg');
}

class _UniDic extends EnhancedFuriganaDictNotifier {
  _UniDic(this.given, this.calls);

  final _Given given;
  final List<String> calls;

  @override
  DownloadTileState build() => DownloadTileState(
    isInstalled: given.installed,
    isDownloading: given.downloading,
    isDeleting: given.deleting,
  );

  @override
  Future<void> checkStatus() async {}

  @override
  Future<void> download(NetworkConsent network) async =>
      calls.add('download unidic');

  @override
  Future<void> delete() async => calls.add('delete unidic');
}

/// One of the five tiles with Download and Delete, and the words it shows.
typedef _Tile = ({
  String name,
  IconData? icon,
  String Function(AppLocalizations) title,
  String Function(AppLocalizations) description,
  String Function(AppLocalizations) installedText,
  String Function(AppLocalizations) deleteTooltip,
  String Function(AppLocalizations) deleteTitle,
  String Function(AppLocalizations) deleteBody,
});

final _tiles = <_Tile>[
  (
    name: 'jmdict',
    icon: null,
    title: (l) => l.downloadsStarterPackJmdict,
    description: (l) => l.downloadsJmdictDescription,
    installedText: (l) => l.downloadsJmdictDownloaded,
    deleteTooltip: (l) => l.downloadsDeleteJmdictTooltip,
    deleteTitle: (l) => l.downloadsDeleteJmdictTitle,
    deleteBody: (l) => l.downloadsDeleteJmdictBody,
  ),
  (
    name: 'kanjidic',
    icon: Icons.font_download_outlined,
    title: (l) => l.downloadsKanjidicTitle,
    description: (l) => l.downloadsKanjidicDescription,
    installedText: (l) => l.downloadsKanjidicDownloaded,
    deleteTooltip: (l) => l.downloadsDeleteKanjidicTooltip,
    deleteTitle: (l) => l.downloadsDeleteKanjidicTitle,
    deleteBody: (l) => l.downloadsDeleteKanjidicBody,
  ),
  (
    name: 'kanjivg',
    icon: Icons.brush_outlined,
    title: (l) => l.downloadsKanjiStrokeOrderTitle,
    description: (l) => l.downloadsKanjiStrokeOrderDescription,
    installedText: (l) => l.downloadsKanjiStrokeOrderDownloaded(count: 11661),
    deleteTooltip: (l) => l.downloadsDeleteKanjiDataTooltip,
    deleteTitle: (l) => l.downloadsDeleteKanjiDataTitle,
    deleteBody: (l) => l.downloadsDeleteKanjiDataBody,
  ),
  (
    name: 'jpdb',
    icon: Icons.bar_chart_outlined,
    title: (l) => l.downloadsStarterPackWordFrequency,
    description: (l) => l.downloadsWordFrequencyDescription,
    installedText: (l) => l.downloadsWordFrequencyDownloaded,
    deleteTooltip: (l) => l.downloadsDeleteFrequencyDataTooltip,
    deleteTitle: (l) => l.downloadsDeleteFrequencyDataTitle,
    deleteBody: (l) => l.downloadsDeleteFrequencyDataBody,
  ),
  (
    name: 'unidic',
    icon: Icons.spellcheck_outlined,
    title: (l) => l.downloadsEnhancedFuriganaTitle,
    description: (l) => l.downloadsEnhancedFuriganaDescription,
    installedText: (l) => l.downloadsEnhancedFuriganaInstalled,
    deleteTooltip: (l) => l.downloadsEnhancedFuriganaRemoveTooltip,
    deleteTitle: (l) => l.downloadsEnhancedFuriganaConfirmRemoveTitle,
    deleteBody: (l) => l.downloadsEnhancedFuriganaConfirmRemoveBody,
  ),
];

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));

  /// The screen [tile] is on, in Japanese, with every tile [given], or
  /// [lowRam]; download and delete calls go to [calls].
  Future<void> pump(
    WidgetTester tester,
    _Tile tile,
    _Given given,
    List<String> calls, {
    bool lowRam = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...fakeDownloadNotifierOverrides(
          [],
          fixed: (dictionary) => _Fixed(dictionary, given, calls),
          kanjiVg: () => _KanjiVg(given, calls),
          enhancedFurigana: () => _UniDic(given, calls),
        ),
        if (lowRam) lowRamModeProvider.overrideWithBuild((ref, _) => true),
      ],
    );
    addTearDown(container.dispose);
    if (tile.name == 'jmdict') {
      await pumpInJapanese(
        tester,
        container,
        home: const Scaffold(body: JmdictDownloadTile()),
      );
    } else {
      await pumpInJapanese(tester, container);
    }
    await tester.pump();
  }

  Finder rowOf(_Tile tile) => find.ancestor(
    of: find.text(tile.title(ja)),
    matching: find.byType(ListTile),
  );
  Finder inRow(_Tile tile, Finder finder) =>
      find.descendant(of: rowOf(tile), matching: finder);
  Finder downloadButton(_Tile tile) =>
      inRow(tile, find.widgetWithText(FilledButton, ja.commonDownload));
  Finder spinner(_Tile tile) =>
      inRow(tile, find.byType(CircularProgressIndicator));

  for (final tile in _tiles) {
    group('the ${tile.name} tile', () {
      testWidgets('offers Download with its description', (tester) async {
        final calls = <String>[];
        await pump(tester, tile, _idle, calls);

        final row = tester.widget<ListTile>(rowOf(tile));
        expect(row.enabled, isTrue);
        expect(row.onTap, isNull);
        expect(inRow(tile, find.text(tile.description(ja))), findsOneWidget);
        expect(
          inRow(tile, find.byType(Icon)),
          tile.icon == null ? findsNothing : findsOneWidget,
        );
        if (tile.icon case final icon?) {
          expect(inRow(tile, find.byIcon(icon)), findsOneWidget);
        }
        expect(downloadButton(tile), findsOneWidget);
        expect(
          tester.widget<FilledButton>(downloadButton(tile)).onPressed,
          isNotNull,
        );
        expect(
          inRow(tile, find.byTooltip(tile.deleteTooltip(ja))),
          findsNothing,
        );
        expect(spinner(tile), findsNothing);

        if (tile.name == 'jmdict') return;
        await tester.tap(downloadButton(tile));
        await tester.pumpAndSettle();
        expect(calls, ['download ${tile.name}']);
      });

      for (final (busy, given) in [
        ('downloading', (installed: false, downloading: true, deleting: false)),
        ('deleting', (installed: true, downloading: false, deleting: true)),
      ]) {
        testWidgets('spins while $busy, with nothing to tap', (tester) async {
          await pump(tester, tile, given, []);

          expect(spinner(tile), findsOneWidget);
          expect(downloadButton(tile), findsNothing);
          expect(
            inRow(tile, find.byTooltip(tile.deleteTooltip(ja))),
            findsNothing,
          );
        });
      }

      testWidgets('installed: says so, and Delete asks first', (tester) async {
        final calls = <String>[];
        await pump(tester, tile, _installed, calls);

        expect(inRow(tile, find.text(tile.installedText(ja))), findsOneWidget);
        expect(downloadButton(tile), findsNothing);
        final delete = inRow(tile, find.byTooltip(tile.deleteTooltip(ja)));
        expect(delete, findsOneWidget);
        expect(
          tester
              .widget<Icon>(
                find.descendant(of: delete, matching: find.byType(Icon)),
              )
              .icon,
          Icons.delete_outline,
        );

        await tester.tap(delete);
        await tester.pumpAndSettle();
        Finder inDialog(String text) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(text),
        );
        expect(inDialog(tile.deleteTitle(ja)), findsOneWidget);
        expect(inDialog(tile.deleteBody(ja)), findsOneWidget);
        await tester.tap(inDialog(ja.commonCancel));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(calls, isEmpty);

        await tester.tap(delete);
        await tester.pumpAndSettle();
        await tester.tap(inDialog(ja.commonDelete));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(calls, ['delete ${tile.name}']);
      });
    });
  }

  final uniDic = _tiles.last;

  testWidgets('in low RAM mode the enhanced furigana tile is off, says why, '
      'and still deletes', (tester) async {
    await pump(tester, uniDic, _idle, [], lowRam: true);

    expect(tester.widget<ListTile>(rowOf(uniDic)).enabled, isFalse);
    expect(inRow(uniDic, find.text(ja.lowRamModeOffHere)), findsOneWidget);
    expect(
      tester.widget<FilledButton>(downloadButton(uniDic)).onPressed,
      isNull,
    );

    await tester.pumpWidget(const SizedBox());
    final calls = <String>[];
    await pump(tester, uniDic, _installed, calls, lowRam: true);
    expect(inRow(uniDic, find.text(ja.lowRamModeOffHere)), findsOneWidget);
    await tester.tap(inRow(uniDic, find.byTooltip(uniDic.deleteTooltip(ja))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ja.commonDelete));
    await tester.pumpAndSettle();
    expect(calls, ['delete unidic']);
  });

  testWidgets('the JMdict tile asks which edition, then downloads it', (
    tester,
  ) async {
    final calls = <String>[];
    final jmdict = _tiles.first;
    await pump(tester, jmdict, _idle, calls);

    await tester.tap(downloadButton(jmdict));
    await tester.pumpAndSettle();
    expect(find.text(ja.downloadsChooseJmdictVariant), findsOneWidget);
    await tester.tap(find.text(ja.downloadsJmdictExamplesTitle));
    await tester.pumpAndSettle();
    expect(calls, ['download jmdict']);
  });
}
