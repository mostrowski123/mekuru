import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
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

    // The JMdict tile's progress never settles: pump a fixed time instead.
    await tester.tap(find.text('Install Starter Pack'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

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

  testWidgets('off Wi-Fi, the JMdict, KANJIDIC and word frequency downloads '
      'ask before using mobile data', (tester) async {
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

    await tester.tap(downloadOf('JMdict English'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('JMdict English'),
      ),
    );
    await agreeTo('16 MB');

    await tester.tap(downloadOf('KANJIDIC'));
    await agreeTo('0.7 MB');

    await tester.scrollUntilVisible(downloadOf('Word Frequency'), 200);
    await tester.tap(downloadOf('Word Frequency'));
    await agreeTo('6 MB');

    expect(started, ['jmdict:jmdictEnglish', 'kanjidic', 'jpdb']);
  });
}
