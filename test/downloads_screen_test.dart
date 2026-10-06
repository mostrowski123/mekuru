import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/starter_pack_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';

import 'shared/fake_download_notifiers.dart';
import 'test_app.dart';

void main() {
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

  testWidgets('off Wi-Fi, the KANJIDIC and word frequency downloads ask '
      'before using mobile data', (tester) async {
    // Each stops if Wi-Fi goes, and its tile then says to tap Download
    // again: that must not go on over mobile data unasked.
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

    await tester.scrollUntilVisible(downloadOf('Word Frequency'), 200);
    await tester.tap(downloadOf('Word Frequency'));
    await agreeTo('6 MB');

    expect(started, ['kanjidic', 'jpdb']);
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
        download: (onProgress) {
          calls.add('download');
          report = onProgress;
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

      expect(find.text('Download failed: Exception: locked'), findsOneWidget);
      expect(inRow(find.byTooltip('Remove')), findsOneWidget);
    });

    testWidgets('downloads after asking about mobile data, cancels until the '
        'file is being verified, and picks High once done', (tester) async {
      mockWifiConnected(false);
      final container = await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Wi-Fi is not connected. The translation model is about 2.6 GB. '
          'Continue using mobile data?',
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

      await tester.tap(inRow(find.byTooltip('Cancel')));
      await tester.pump();
      expect(calls, ['download', 'cancel']);

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

    testWidgets('a failed download shows the error and offers Download again', (
      tester,
    ) async {
      mockWifiConnected(true);
      await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      downloadDone.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      expect(find.text('Download failed: Exception: boom'), findsOneWidget);
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
