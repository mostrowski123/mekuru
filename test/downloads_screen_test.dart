import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/settings/data/services/jpdb_freq_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/fixed_dictionary_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/starter_pack_card.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/manga/data/services/model_download_job.dart';

import 'shared/fake_download_notifiers.dart';
import 'test_app.dart';

/// Standard translation, not downloaded, whose download fails with [error].
class _FailingStandardTranslation implements TranslationEngine {
  _FailingStandardTranslation(this.error);

  final Object error;

  @override
  Future<TranslationStatus> status(String target) async =>
      TranslationStatus.needsDownload;

  @override
  Future<void> download(String target, NetworkConsent network) async =>
      throw error;

  @override
  Future<String> translate(String text, String target) async => '';
}

/// Standard translation, downloaded.
class _InstalledStandardTranslation implements TranslationEngine {
  @override
  Future<TranslationStatus> status(String target) async =>
      TranslationStatus.installed;

  @override
  Future<void> download(String target, NetworkConsent network) async {}

  @override
  Future<String> translate(String text, String target) async => '';
}

void main() {
  testWidgets('in Japanese, a translation remove that fails says so, not '
      "that a download didn't finish", (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    debugDeviceLowOnMemory = false;
    addTearDown(() => debugDeviceLowOnMemory = null);
    debugTranslationEngine = _InstalledStandardTranslation();
    addTearDown(() => debugTranslationEngine = null);
    var deletes = 0;
    debugDeleteTranslation = () async {
      deletes++;
      throw const FileSystemException('locked', '/data/translation_models');
    };
    addTearDown(() => debugDeleteTranslation = null);
    final container = ProviderContainer(
      overrides: fakeDownloadNotifierOverrides([]),
    );
    addTearDown(container.dispose);
    await pumpInJapanese(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, ja.downloadsSentenceTranslationTitle),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();

    expect(deletes, 1);
    expect(find.text(ja.downloadsDeleteFailed), findsOneWidget);
    expect(find.text(ja.downloadNotFinished), findsNothing);
    expect(untranslatedDownloadText, findsNothing);
  });

  testWidgets('starter pack starts both downloads together', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockWifiConnected(true);
    final started = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeDownloadNotifierOverrides(started),
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.descendant(
        of: find.byType(StarterPackCard),
        matching: find.text('Jitendex'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Install Starter Pack'));
    await tester.pumpAndSettle();

    expect(started, unorderedEquals(<String>['catalog:jitendex', 'jpdb']));
    final list = tester.widget<ListView>(find.byType(ListView));
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    expect(children.first, isNot(isA<LocalOcrDownloadTile>()));
    expect(children[children.length - 2], isA<LocalOcrDownloadTile>());
  });

  testWidgets('off Wi-Fi the starter pack asks before using mobile data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    mockWifiConnected(false);
    final started = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeDownloadNotifierOverrides(started),
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );
    await tester.pump();
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    await tester.tap(find.text('Install Starter Pack'));
    await tester.pumpAndSettle();
    expect(find.text('Download over mobile data?'), findsOneWidget);
    expect(find.textContaining('about 45 MB'), findsOneWidget);

    await tester.tap(inDialog('Cancel'));
    await tester.pumpAndSettle();
    expect(started, isEmpty);

    await tester.tap(find.text('Install Starter Pack'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Download'));
    await tester.pumpAndSettle();
    expect(started, unorderedEquals(<String>['catalog:jitendex', 'jpdb']));
  });

  testWidgets('while JMdict English downloads the starter pack adds only '
      'frequency', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockWifiConnected(true);
    final started = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeDownloadNotifierOverrides(
          started,
          jmdictDownloading: true,
        ),
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Install Starter Pack'));
    await tester.pumpAndSettle();

    expect(started, ['jpdb']);
  });

  for (final (row, title) in [
    ('JMdict English', 'JMdict [2026-10-03]'),
    ('Jitendex', 'Jitendex.org [2026-10-03]'),
  ]) {
    testWidgets('with $row installed the starter pack adds only frequency', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      mockWifiConnected(true);
      final started = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: fakeDownloadNotifierOverrides(
            started,
            installed: [
              DictionaryMeta(
                id: 1,
                name: title,
                isEnabled: true,
                dateImported: DateTime(2026, 10, 3),
                sortOrder: 0,
                isHidden: false,
              ),
            ],
          ),
          child: buildLocalizedTestApp(home: const DownloadsScreen()),
        ),
      );
      await tester.pump();
      Finder inCard(Finder finder) =>
          find.descendant(of: find.byType(StarterPackCard), matching: finder);
      expect(inCard(find.text(row)), findsOneWidget);
      expect(inCard(find.byIcon(Icons.check_circle)), findsOneWidget);

      await tester.tap(find.text('Install Starter Pack'));
      await tester.pumpAndSettle();

      expect(started, ['jpdb']);
    });
  }

  testWidgets('in Japanese, word frequency switched off in the dictionary '
      'list says so on its row and the starter pack, and how to switch it '
      'on', (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    DictionaryMeta meta(int id, String name, {required bool on}) =>
        DictionaryMeta(
          id: id,
          name: name,
          isEnabled: on,
          dateImported: DateTime(2026, 11, 22),
          sortOrder: id,
          isHidden: false,
        );
    final started = <String>[];
    final container = ProviderContainer(
      overrides: fakeDownloadNotifierOverrides(
        started,
        installed: [
          meta(1, 'Jitendex.org [2026-10-03]', on: true),
          meta(2, JpdbFreqDownloadService.dictionaryName, on: false),
        ],
        fixed: (dictionary) => dictionary == FixedDictionary.jpdb
            ? FakeFixedDictionaryNotifier(
                dictionary,
                (_) => started.add('jpdb'),
                initial: const FixedDictionaryState(isImported: true),
              )
            : null,
      ),
    );
    addTearDown(container.dispose);
    await pumpInJapanese(tester, container);
    await tester.pump();
    Finder inCard(Finder finder) =>
        find.descendant(of: find.byType(StarterPackCard), matching: finder);
    Finder inRow(Finder finder) => find.descendant(
      of: find.ancestor(
        of: find.byIcon(Icons.bar_chart_outlined),
        matching: find.byType(ListTile),
      ),
      matching: finder,
    );

    // Was: "downloaded" and a tick, with nothing to say why results aren't
    // ranked.
    expect(inRow(find.text(ja.downloadsWordFrequencyDownloaded)), findsNothing);
    expect(
      inRow(find.text(ja.downloadsWordFrequencySwitchedOff)),
      findsOneWidget,
    );
    expect(
      inCard(find.text(ja.downloadsWordFrequencySwitchedOff)),
      findsOneWidget,
    );
    // Only Jitendex is ticked.
    expect(inCard(find.byIcon(Icons.check_circle)), findsOneWidget);
    // Installed: nothing to download, so nothing is offered or started.
    expect(inRow(find.text(ja.commonDownload)), findsNothing);
    expect(started, isEmpty);

    await tester.tap(inCard(find.text(ja.commonManageDictionaries)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DictionaryManagerScreen), findsOneWidget);
  });

  testWidgets('word frequency switched on reads as downloaded, with no '
      'switch-on hint', (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final container = ProviderContainer(
      overrides: fakeDownloadNotifierOverrides(
        [],
        installed: [
          DictionaryMeta(
            id: 2,
            name: JpdbFreqDownloadService.dictionaryName,
            isEnabled: true,
            dateImported: DateTime(2026, 11, 22),
            sortOrder: 2,
            isHidden: false,
          ),
        ],
        fixed: (dictionary) => dictionary == FixedDictionary.jpdb
            ? FakeFixedDictionaryNotifier(
                dictionary,
                (_) {},
                initial: const FixedDictionaryState(isImported: true),
              )
            : null,
      ),
    );
    addTearDown(container.dispose);
    await pumpInJapanese(tester, container);
    await tester.pump();

    expect(find.text(ja.downloadsWordFrequencyDownloaded), findsOneWidget);
    expect(find.text(ja.downloadsWordFrequencySwitchedOff), findsNothing);
    expect(
      find.descendant(
        of: find.byType(StarterPackCard),
        matching: find.text(ja.commonManageDictionaries),
      ),
      findsNothing,
    );
  });

  testWidgets('off Wi-Fi, the KANJIDIC, stroke order, word frequency and '
      'enhanced furigana downloads ask before using mobile data', (
    tester,
  ) async {
    // A dictionary download stops if Wi-Fi goes, and its tile then says to
    // tap Download again: that must not go on over mobile data unasked.
    SharedPreferences.setMockInitialValues({});
    mockWifiConnected(false);
    final started = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeDownloadNotifierOverrides(started),
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );
    await tester.pump();
    Finder downloadOf(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
      matching: find.text('Download'),
    );
    Future<void> agreeTo(String size) async {
      await tester.pumpAndSettle();
      expect(find.textContaining('about $size'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Download'),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(downloadOf('KANJIDIC'));
    await agreeTo('0.7 MB');

    await tester.scrollUntilVisible(downloadOf('Kanji Stroke Order'), 200);
    await tester.tap(downloadOf('Kanji Stroke Order'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stroke order data is about'), findsOneWidget);
    await agreeTo('22 MB');

    await tester.scrollUntilVisible(downloadOf('Word Frequency'), 200);
    await tester.tap(downloadOf('Word Frequency'));
    await agreeTo('6 MB');

    await tester.scrollUntilVisible(
      downloadOf('Enhanced Furigana Dictionary'),
      200,
    );
    await tester.tap(downloadOf('Enhanced Furigana Dictionary'));
    await agreeTo('45 MB');

    expect(started, ['kanjidic', 'kanjivg', 'jpdb', 'enhanced_furigana']);
  });

  testWidgets('the Japanese translation row: Wi-Fi going says what it '
      'kept', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockWifiConnected(true);
    debugDeviceLowOnMemory = false;
    addTearDown(() => debugDeviceLowOnMemory = null);
    debugTranslationEngine = _FailingStandardTranslation(
      const WifiLostException(),
    );
    addTearDown(() => debugTranslationEngine = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeDownloadNotifierOverrides([]),
        child: buildLocalizedTestApp(home: const DownloadsScreen()),
      ),
    );
    await tester.pump();
    const title = 'Japanese translation';
    await tester.scrollUntilVisible(find.text(title), 200);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, title),
        matching: find.text('Download'),
      ),
    );
    await tester.pumpAndSettle();

    // The partial files are kept, so the next tap continues them.
    expect(find.textContaining('try again'), findsNothing);
    expect(
      find.text(
        'The download stopped because Wi-Fi disconnected. Finished files are '
        'kept. Tap Download to continue.',
      ),
      findsOneWidget,
    );
  });

  group('high-quality translation row', () {
    const title = 'High-quality translation (Gemma 4)';
    var installed = false;
    var deleteFails = false;
    var hasFiles = false;
    var cancelStops = false;
    final calls = <String>[];
    late Completer<void> downloadDone;
    late void Function(double fraction) report;
    late void Function(double fraction, JobWait wait) progress;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      installed = false;
      deleteFails = false;
      hasFiles = false;
      cancelStops = false;
      calls.clear();
      debugDeviceLowOnMemory = false;
      debugGemmaModelOps = (
        installed: () async => installed,
        download: (onProgress, _) {
          calls.add('download');
          progress = onProgress;
          report = (fraction) => onProgress(fraction, JobWait.none);
          // Made here, in the test's zone, so completing it reaches pump().
          downloadDone = Completer<void>();
          return downloadDone.future;
        },
        delete: () async {
          calls.add('delete');
          if (deleteFails) throw Exception('locked');
          installed = false;
        },
        hasFiles: () async => hasFiles,
        cancel: () {
          calls.add('cancel');
          // What force-closing the HttpClient does to the running download.
          if (cancelStops) downloadDone.completeError(StateError('closed'));
          return true;
        },
        pending: () async => false,
      );
    });

    tearDown(() {
      debugGemmaModelOps = null;
      debugDeviceLowOnMemory = null;
    });

    Future<ProviderContainer> pumpDownloads(
      WidgetTester tester, {
      TranslationModelChoice choice = TranslationModelChoice.standard,
    }) async {
      final container = ProviderContainer(
        overrides: fakeDownloadNotifierOverrides([]),
      );
      addTearDown(container.dispose);
      container.read(translationModelProvider.notifier).setChoice(choice);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(home: const DownloadsScreen()),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(find.text(title), 200);
      await tester.pumpAndSettle();
      return container;
    }

    Finder inRow(Finder finder) => find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: finder,
    );
    final progressBar = find.byWidgetPredicate(
      (w) => w is LinearProgressIndicator && w.semanticsLabel == title,
    );

    testWidgets('removes an installed model and switches High to Standard', (
      tester,
    ) async {
      installed = true;
      final container = await pumpDownloads(
        tester,
        choice: TranslationModelChoice.high,
      );

      await tester.tap(inRow(find.byTooltip('Remove')));
      await tester.pumpAndSettle();

      expect(calls, ['delete']);
      expect(container.read(gemmaDownloadProvider), isA<GemmaNotInstalled>());
      expect(inRow(find.text('Download')), findsOneWidget);
      expect(
        container.read(translationModelProvider),
        TranslationModelChoice.standard,
      );
    });

    testWidgets('a failed removal says so and keeps the model', (tester) async {
      installed = true;
      deleteFails = true;
      await pumpDownloads(tester);

      await tester.tap(inRow(find.byTooltip('Remove')));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't delete the files. Try again."),
        findsOneWidget,
      );
      expect(inRow(find.byTooltip('Remove')), findsOneWidget);
    });

    testWidgets('downloads after asking about mobile data, offers Cancel '
        'until the file is being verified, and picks High once done', (
      tester,
    ) async {
      mockWifiConnected(false);
      final container = await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "The translation model is about 2.6 GB. You're on mobile data or a "
          'hotspot, so downloading it may use your data plan.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Download'),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, ['download']);
      expect(container.read(gemmaDownloadProvider), isA<GemmaDownloading>());
      expect(
        container.read(translationModelProvider),
        TranslationModelChoice.standard,
      );
      expect(inRow(find.text('High quality: downloading 0%')), findsOneWidget);
      expect(progressBar, findsOneWidget);
      expect(inRow(find.byTooltip('Remove')), findsNothing);
      // Tapping it is the partial-file test below: a cancel keeps Standard.
      expect(inRow(find.byTooltip('Cancel')), findsOneWidget);

      // At 100% the file is being checked and there is nothing to cancel.
      report(1);
      await tester.pump();
      expect(inRow(find.byTooltip('Cancel')), findsNothing);
      expect(progressBar, findsOneWidget);

      installed = true;
      downloadDone.complete();
      await tester.pumpAndSettle();
      expect(
        container.read(translationModelProvider),
        TranslationModelChoice.high,
      );
    });

    testWidgets('a job waiting for Wi-Fi says so and offers Cancel', (
      tester,
    ) async {
      mockWifiConnected(true);
      await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      progress(0.3, JobWait.wifi);
      await tester.pump();

      expect(
        inRow(
          find.text('Waiting for Wi-Fi. Cancel and resume to use mobile data.'),
        ),
        findsOneWidget,
      );
      expect(inRow(find.byTooltip('Cancel')), findsOneWidget);

      progress(0.4, JobWait.none);
      await tester.pump();
      expect(inRow(find.text('High quality: downloading 40%')), findsOneWidget);
      downloadDone.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a job between attempts, or waiting for any network, says so '
        'and offers Cancel', (tester) async {
      mockWifiConnected(true);
      await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      progress(0.3, JobWait.retry);
      await tester.pump();

      expect(
        inRow(find.text('The download was interrupted. Trying again shortly…')),
        findsOneWidget,
      );
      expect(inRow(find.textContaining('30%')), findsNothing);
      expect(inRow(find.byTooltip('Cancel')), findsOneWidget);

      progress(0.3, JobWait.connection);
      await tester.pump();
      expect(
        inRow(find.text('Waiting for an internet connection.')),
        findsOneWidget,
      );
      downloadDone.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a failed download shows the error and offers Download again', (
      tester,
    ) async {
      mockWifiConnected(true);
      await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      downloadDone.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      // An error with no message of its own: not its text.
      expect(
        find.text("The download didn't finish. Try again."),
        findsOneWidget,
      );
      expect(
        inRow(
          find.text(
            'A larger model for better sentence translations, for phones '
            'with plenty of memory. (2.6 GB)',
          ),
        ),
        findsOneWidget,
      );
      expect(inRow(find.text('Download')), findsOneWidget);
      // Whatever it left behind can go.
      expect(inRow(find.byTooltip('Remove')), findsOneWidget);
    });

    testWidgets('a download without room says how much more it needs', (
      tester,
    ) async {
      mockWifiConnected(true);
      final container = await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      downloadDone.completeError(
        const InsufficientSpaceException(neededBytes: 1500000000),
      );
      await tester.pumpAndSettle();

      expect(container.read(gemmaDownloadProvider), isA<GemmaDownloadFailed>());
      expect(
        find.textContaining('Not enough free space on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('a cancelled download offers to remove its partial file', (
      tester,
    ) async {
      mockWifiConnected(true);
      cancelStops = true;
      await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      hasFiles = true;
      await tester.tap(inRow(find.byTooltip('Cancel')));
      await tester.pumpAndSettle();

      expect(inRow(find.text('Download')), findsOneWidget);
      await tester.tap(inRow(find.byTooltip('Remove')));
      await tester.pumpAndSettle();

      expect(calls, ['download', 'cancel', 'delete']);
      expect(inRow(find.byTooltip('Remove')), findsNothing);
      expect(inRow(find.text('Download')), findsOneWidget);
    });
  });
}
