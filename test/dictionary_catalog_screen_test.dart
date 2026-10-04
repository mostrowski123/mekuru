import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_catalog_screen.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';

import 'shared/fake_download_notifiers.dart';
import 'test_app.dart';

void main() {
  late List<CatalogDictionary> started;
  late List<CatalogDictionary> replacingJmdict;
  late List<YomitanDictType> jmdictStarted;
  late List<int> deleted;

  setUp(() {
    started = [];
    replacingJmdict = [];
    jmdictStarted = [];
    deleted = [];
  });

  /// Installed dictionaries get ids 1, 2, … in [installed] order, then
  /// [otherTitles] (dictionaries outside the catalog, e.g. JMdict).
  Future<void> pumpCatalog(
    WidgetTester tester, {
    List<CatalogDictionary> installed = const [],
    List<String> otherTitles = const [],
    CatalogDownloadState afterDownload = const CatalogDownloadState(),
  }) async {
    final titles = [for (final entry in installed) entry.title, ...otherTitles];
    final metas = [
      for (final (i, title) in titles.indexed)
        DictionaryMeta(
          id: i + 1,
          name: '$title [2026-09-01]',
          isEnabled: true,
          dateImported: DateTime(2026, 9, 1),
          sortOrder: i,
          isHidden: false,
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionariesProvider.overrideWith((ref) => Stream.value(metas)),
          for (final entry in CatalogDictionary.values)
            catalogDownloadProvider(entry).overrideWith(
              () => FakeCatalogDownloadNotifier(
                entry,
                started.add,
                result: afterDownload,
                onDelete: deleted.add,
                onReplaceJmdict: replacingJmdict.add,
              ),
            ),
          jmdictProvider.overrideWith(
            () => FakeJmdictNotifier(jmdictStarted.add, const JmdictState()),
          ),
        ],
        child: buildLocalizedTestApp(home: const DictionaryCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tileOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile));
  Finder downloadButtonOf(String name) =>
      find.descendant(of: tileOf(name), matching: find.text('Download'));
  Finder deleteOf(String name) => find.descendant(
    of: tileOf(name),
    matching: find.byTooltip('Delete Dictionary'),
  );

  testWidgets('lists every section, then the guide links', (tester) async {
    await pumpCatalog(tester);

    for (final text in [
      'Japanese–English',
      'Jitendex',
      'JMdict English',
      'Japanese–Japanese',
      'Names',
      'JMnedict',
      'Other Languages',
      'Find More Dictionaries',
      for (final guide in dictionaryGuides) guide.name,
    ]) {
      await tester.scrollUntilVisible(find.text(text), 200);
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('Download starts that dictionary; installed ones offer Delete', (
    tester,
  ) async {
    mockWifiConnected(true);
    await pumpCatalog(tester, installed: [CatalogDictionary.wiktionaryEnglish]);

    expect(deleteOf('Wiktionary (English)'), findsOneWidget);
    expect(downloadButtonOf('Wiktionary (English)'), findsNothing);

    await tester.tap(downloadButtonOf('Jitendex'));
    await tester.pumpAndSettle();
    expect(started, [CatalogDictionary.jitendex]);
  });

  testWidgets('Delete asks first, then deletes that dictionary', (
    tester,
  ) async {
    // A newer version is installed by deleting the dictionary and
    // downloading it again.
    await pumpCatalog(
      tester,
      installed: [
        CatalogDictionary.jitendex,
        CatalogDictionary.wiktionaryEnglish,
      ],
    );

    await tester.tap(deleteOf('Wiktionary (English)'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delete "Wiktionary (English)"'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);

    await tester.tap(deleteOf('Wiktionary (English)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, [2]);
    // Gone before the list stream drops it: Drift refetches the list only
    // after every delete queued behind this one.
    expect(downloadButtonOf('Wiktionary (English)'), findsOneWidget);
  });

  testWidgets('Jitendex over JMdict asks first: cancel, download anyway or '
      'replace JMdict', (tester) async {
    mockWifiConnected(true);
    await pumpCatalog(
      tester,
      // Another language's JMdict is not the English one Jitendex repeats.
      otherTitles: ['JMdict (Spanish)', 'JMdict'],
    );
    Future<void> chooseOnJitendex(String button) async {
      await tester.tap(downloadButtonOf('Jitendex'));
      await tester.pumpAndSettle();
      expect(find.text('You already have JMdict'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(button),
        ),
      );
      await tester.pumpAndSettle();
    }

    await chooseOnJitendex('Cancel');
    expect(started, isEmpty);

    await chooseOnJitendex('Download anyway');
    expect(started, [CatalogDictionary.jitendex]);
    expect(replacingJmdict, isEmpty);

    await chooseOnJitendex('Replace JMdict');
    expect(replacingJmdict, [CatalogDictionary.jitendex]);
    expect(deleted, isEmpty, reason: 'JMdict goes only once Jitendex is in');
  });

  testWidgets('Jitendex without English JMdict downloads without asking', (
    tester,
  ) async {
    mockWifiConnected(true);
    await pumpCatalog(tester, otherTitles: ['JMdict (Spanish)']);

    await tester.tap(downloadButtonOf('Jitendex'));
    await tester.pumpAndSettle();

    expect(find.text('You already have JMdict'), findsNothing);
    expect(started, [CatalogDictionary.jitendex]);
  });

  testWidgets('a download stopped by Wi-Fi going says so', (tester) async {
    mockWifiConnected(true);
    await pumpCatalog(
      tester,
      afterDownload: const CatalogDownloadState(failure: WifiLostException()),
    );

    await tester.tap(downloadButtonOf('Jitendex'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The download stopped because Wi-Fi disconnected. '
        'Tap Download to try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an install without enough free space says how much more '
      'is needed', (tester) async {
    mockWifiConnected(true);
    await pumpCatalog(
      tester,
      afterDownload: const CatalogDownloadState(
        failure: InsufficientSpaceException(neededBytes: 500 << 20),
      ),
    );

    await tester.tap(downloadButtonOf('Jitendex'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Not enough free space on this device. About 500 MB more is needed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('off Wi-Fi a download asks before using mobile data', (
    tester,
  ) async {
    mockWifiConnected(false);
    await pumpCatalog(tester);
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    await tester.tap(downloadButtonOf('Jitendex'));
    await tester.pumpAndSettle();
    expect(find.text('Download over mobile data?'), findsOneWidget);
    expect(find.textContaining('about 39 MB'), findsOneWidget);

    await tester.tap(inDialog('Cancel'));
    await tester.pumpAndSettle();
    expect(started, isEmpty);

    await tester.tap(downloadButtonOf('Jitendex'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Download'));
    await tester.pumpAndSettle();
    expect(started, [CatalogDictionary.jitendex]);
  });

  testWidgets('off Wi-Fi the JMdict English download asks before using '
      'mobile data', (tester) async {
    mockWifiConnected(false);
    await pumpCatalog(tester);

    await tester.tap(downloadButtonOf('JMdict English'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('JMdict English'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('about 16 MB'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Download'),
      ),
    );
    await tester.pumpAndSettle();

    expect(jmdictStarted, [YomitanDictType.jmdictEnglish]);
  });
}
