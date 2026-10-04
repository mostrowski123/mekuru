import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_catalog_screen.dart';

import 'shared/fake_download_notifiers.dart';
import 'test_app.dart';

void main() {
  late List<CatalogDictionary> started;

  setUp(() => started = []);

  Future<void> pumpCatalog(
    WidgetTester tester, {
    Set<CatalogDictionary> installed = const {},
    CatalogDownloadState afterDownload = const CatalogDownloadState(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          installedCatalogDictionariesProvider.overrideWithValue(installed),
          for (final entry in CatalogDictionary.values)
            catalogDownloadProvider(entry).overrideWith(
              () => _FakeCatalogDownloadNotifier(
                entry,
                started.add,
                afterDownload,
              ),
            ),
        ],
        child: buildLocalizedTestApp(home: const DictionaryCatalogScreen()),
      ),
    );
    await tester.pump();
  }

  Finder tileOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile));
  Finder downloadButtonOf(String name) =>
      find.descendant(of: tileOf(name), matching: find.text('Download'));

  testWidgets('lists every section, then the guide links', (tester) async {
    await pumpCatalog(tester);

    for (final text in [
      'Japanese–English',
      'Jitendex',
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

  testWidgets('Download starts that dictionary; installed ones show a check', (
    tester,
  ) async {
    mockWifiConnected(true);
    await pumpCatalog(tester, installed: {CatalogDictionary.wiktionaryEnglish});

    expect(
      find.descendant(
        of: tileOf('Wiktionary (English)'),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(downloadButtonOf('Wiktionary (English)'), findsNothing);

    await tester.tap(downloadButtonOf('Jitendex'));
    await tester.pumpAndSettle();
    expect(started, [CatalogDictionary.jitendex]);
  });

  testWidgets('an install without enough free space says how much more '
      'is needed', (tester) async {
    mockWifiConnected(true);
    await pumpCatalog(
      tester,
      afterDownload: const CatalogDownloadState(neededBytes: 500 << 20),
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
}

class _FakeCatalogDownloadNotifier extends CatalogDownloadNotifier {
  _FakeCatalogDownloadNotifier(super.entry, this.onDownload, this.result);

  final void Function(CatalogDictionary entry) onDownload;
  final CatalogDownloadState result;

  @override
  Future<void> download() async {
    onDownload(entry);
    state = result;
  }
}
