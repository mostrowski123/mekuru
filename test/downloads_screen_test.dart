import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/starter_pack_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';

import 'shared/fake_download_notifiers.dart';
import 'shared/reader_settings_test_helpers.dart';
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
    final calls = <String>[];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      installed = false;
      calls.clear();
      debugGemmaModelOps = (
        installed: () async => installed,
        // Never finishes, so the row stays on "downloading".
        download: (_) {
          calls.add('download');
          return Completer<void>().future;
        },
        delete: () async {
          calls.add('delete');
          installed = false;
        },
        cancel: () {
          calls.add('cancel');
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

    testWidgets('removes an installed model and keeps High chosen', (
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

      // Settings now offers the download again, still on High.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(home: const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await scrollSettingsTo(tester, find.text('Sentence translation'));
      expect(
        container.read(translationModelProvider),
        TranslationModelChoice.high,
      );
      expect(
        find.text('High quality: tap to download (2.6 GB)'),
        findsOneWidget,
      );
    });

    testWidgets('downloads after asking about mobile data, and cancels', (
      tester,
    ) async {
      debugDeviceLowOnMemory = false;
      mockWifiConnected(false);
      final container = await pumpDownloads(tester);

      await tester.tap(inRow(find.text('Download')));
      await tester.pumpAndSettle();
      expect(find.textContaining('about 2.6 GB'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Download'),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, ['download']);
      expect(container.read(gemmaDownloadProvider), isA<GemmaDownloading>());
      expect(inRow(find.text('High quality: downloading 0%')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(inRow(find.byTooltip('Remove')), findsNothing);

      await tester.tap(inRow(find.byTooltip('Cancel')));
      await tester.pump();
      expect(calls, ['download', 'cancel']);
    });
  });
}
