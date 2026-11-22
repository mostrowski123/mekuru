import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_catalog_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/catalog_dictionary_tile.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download.dart' show TileAction;

import 'shared/fake_download_notifiers.dart';
import 'shared/test_database.dart';
import 'test_app.dart';

/// A database whose dictionary deletes fail, as a full or locked one does.
class _FailingDeleteRepository extends DictionaryRepository {
  _FailingDeleteRepository(super.db);

  @override
  Future<void> deleteDictionary(int dictionaryId) async =>
      throw const FileSystemException('locked');
}

/// The dictionaries [listed] (a [StateError] while null), whose deletes go
/// through without a database.
class _ListedRepository extends DictionaryRepository {
  _ListedRepository(super.db);

  List<DictionaryMeta>? listed;

  @override
  Future<List<DictionaryMeta>> getAllDictionaries() async =>
      listed ?? (throw StateError('database closed'));

  @override
  Future<void> deleteDictionary(int dictionaryId) async {}
}

void main() {
  test('every entry downloads over https and has a distinct title', () {
    for (final entry in CatalogDictionary.values) {
      expect(entry.url, startsWith('https://'), reason: entry.displayName);
      expect(
        entry.sourceUrl,
        startsWith('https://'),
        reason: entry.displayName,
      );
    }
    final titles = CatalogDictionary.values.map((e) => e.title).toList();
    expect(titles.toSet(), hasLength(titles.length));
  });

  test('titles match with or without a revision, and nothing else', () {
    const jmnedict = CatalogDictionary.jmnedict;
    expect(jmnedict.matchesTitle('JMnedict'), isTrue);
    expect(jmnedict.matchesTitle('JMnedict [2026-10-03]'), isTrue);
    expect(jmnedict.matchesTitle('JMnedict (old)'), isFalse);
    expect(jmnedict.matchesTitle('JMdict [2026-10-03]'), isFalse);
    expect(
      CatalogDictionary.forTitle('Jitendex.org [2026-10-03]'),
      CatalogDictionary.jitendex,
    );
    expect(
      CatalogDictionary.forTitle('wty-ja-ja'),
      CatalogDictionary.wiktionaryJapanese,
    );
    expect(CatalogDictionary.forTitle('JMdict [2026-10-03]'), isNull);
  });

  test('catalog editions are installed as themselves, never as the English '
      'JMdict or KANJIDIC', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    for (final entry in CatalogDictionary.values) {
      await repo.insertDictionary('${entry.title} [2026-10-03]');
    }
    final installed = await repo.getAllDictionaries();

    for (final entry in CatalogDictionary.values) {
      expect(entry.isInstalledIn(installed), isTrue, reason: entry.displayName);
    }
    for (final type in YomitanDictType.values) {
      expect(
        await YomitanDictDownloadService.isImported(type, repo),
        isFalse,
        reason: type.name,
      );
    }
  });

  test('KANJIDIC editions keep the name start kanji parsing looks for', () {
    for (final entry in CatalogDictionary.values) {
      if (entry.title.startsWith('KANJIDIC')) {
        expect(entry.displayName, startsWith('KANJIDIC'));
      }
    }
  });

  test('display names use catalog names and drop revisions', () {
    const shown = {
      'Jitendex.org [2026-10-03]': 'Jitendex',
      'wty-ja-en': 'Wiktionary (English)',
      'JMdict (Spanish) [2026-10-03]': 'JMdict (Español)',
      'JMdict [2026-10-03]': 'JMdict',
      'KANJIDIC [2026-276]': 'KANJIDIC',
      'Old Dict [2024.01.02]': 'Old Dict',
      'JPDBv2㋕': 'JPDBv2㋕',
      'My notes [draft]': 'My notes [draft]',
    };
    shown.forEach(
      (stored, name) =>
          expect(dictionaryDisplayName(stored), name, reason: stored),
    );
  });

  test('the version a display name leaves out', () {
    DictionaryMeta meta(String name, {String? revision}) => DictionaryMeta(
      id: 1,
      name: name,
      isEnabled: true,
      dateImported: DateTime(2026, 10, 4),
      sortOrder: 0,
      isHidden: false,
      revision: revision,
    );

    expect(
      dictionaryVersion(meta('JMdict [2026-10-03]', revision: 'JMdict.2026')),
      '2026-10-03',
    );
    expect(
      dictionaryVersion(meta('wty-ja-en', revision: '2026.10.02')),
      '2026.10.02',
    );
    expect(dictionaryVersion(meta('My dictionary')), isNull);
  });

  test('deleting a catalog dictionary removes it', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = DictionaryRepository(db);
    final id = await repo.insertDictionary('Jitendex.org [2026-10-03]');
    final container = ProviderContainer(
      overrides: [dictionaryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final download = catalogDownloadProvider(CatalogDictionary.jitendex);

    await container.read(download.notifier).delete(id);

    expect(await repo.getAllDictionaries(), isEmpty);
    expect(container.read(download).isDeleting, isFalse);
    expect(container.read(download).deletedId, id);
  });

  testWidgets('in Japanese, a failed delete says so and keeps Delete', (
    tester,
  ) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final db = createTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryRepositoryProvider.overrideWithValue(
            _FailingDeleteRepository(db),
          ),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value([
              DictionaryMeta(
                id: 1,
                name: 'Jitendex.org [2026-10-03]',
                isEnabled: true,
                dateImported: DateTime(2026, 10, 3),
                sortOrder: 0,
                isHidden: false,
              ),
            ]),
          ),
        ],
        child: buildLocalizedTestApp(
          home: const Scaffold(
            body: CatalogDictionaryTile(entry: CatalogDictionary.jitendex),
          ),
          locale: const Locale('ja'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip(ja.dictionaryManagerDeleteTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ja.commonDelete));
    await tester.pumpAndSettle();

    expect(find.text(ja.downloadsDeleteFailed), findsOneWidget);
    expect(untranslatedDownloadText, findsNothing);
    expect(find.textContaining('locked'), findsNothing);
    // Still installed, so Delete can be tried again.
    expect(find.byTooltip(ja.dictionaryManagerDeleteTitle), findsOneWidget);
  });

  testWidgets('in Japanese, a download and a delete each say how they went', (
    tester,
  ) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = _ListedRepository(db);
    // The list the row watches, as the repository's stream feeds it.
    final listed = StreamController<List<DictionaryMeta>>();
    addTearDown(listed.close);
    listed.add(const []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryRepositoryProvider.overrideWithValue(repo),
          dictionariesProvider.overrideWith((ref) => listed.stream),
        ],
        child: buildLocalizedTestApp(
          home: const Scaffold(
            body: CatalogDictionaryTile(entry: CatalogDictionary.jitendex),
          ),
          locale: const Locale('ja'),
        ),
      ),
    );
    await tester.pump();
    final download = ProviderScope.containerOf(
      tester.element(find.byType(CatalogDictionaryTile)),
    ).read(catalogDownloadProvider(CatalogDictionary.jitendex).notifier);

    // Fails before it fetches anything; never the error's text.
    await download.download(NetworkConsent.mobileData);
    await tester.pump();
    expect(find.text(ja.downloadNotFinished), findsOneWidget);
    expect(find.textContaining('closed'), findsNothing);

    // Installed meanwhile: nothing left to fetch, so it finishes.
    repo.listed = [
      DictionaryMeta(
        id: 1,
        name: 'Jitendex.org [2026-10-03]',
        isEnabled: true,
        dateImported: DateTime(2026, 10, 3),
        sortOrder: 0,
        isHidden: false,
      ),
    ];
    listed.add(repo.listed!);
    await download.download(NetworkConsent.mobileData);
    await tester.pump();
    expect(find.text(ja.downloadsDownloadComplete), findsOneWidget);
    expect(find.text(ja.downloadNotFinished), findsNothing);

    await download.delete(1);
    await tester.pump();
    expect(find.text(ja.downloadsDeleted), findsOneWidget);
    expect(untranslatedDownloadText, findsNothing);
  });

  group('Jitendex replacing JMdict', () {
    final download = catalogDownloadProvider(CatalogDictionary.jitendex);

    /// Downloads Jitendex, replacing JMdict, with [titles] installed; returns
    /// the titles left and the download's state.
    Future<(List<String>, CatalogDownloadState)> replaceOver(
      List<String> titles,
    ) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = DictionaryRepository(db);
      for (final title in titles) {
        await repo.insertDictionary(title);
      }
      final container = ProviderContainer(
        overrides: [dictionaryRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(download.notifier)
          .download(NetworkConsent.mobileData, replaceJmdict: true);
      final left = await repo.getAllDictionaries();
      return ([for (final d in left) d.name], container.read(download));
    }

    test('deletes English JMdict once Jitendex is installed', () async {
      // Jitendex is installed already, so nothing is downloaded.
      final (left, state) = await replaceOver([
        'JMdict (Spanish) [2026-10-03]',
        'JMdict [2026-10-03]',
        'Jitendex.org [2026-10-03]',
      ]);

      expect(left, [
        'JMdict (Spanish) [2026-10-03]',
        'Jitendex.org [2026-10-03]',
      ]);
      expect(state.outcome, (action: TileAction.download, error: null));
    });

    test('keeps JMdict when the Jitendex download fails', () async {
      // No network or platform plugins in unit tests: the download fails.
      final (left, state) = await replaceOver(['JMdict [2026-10-03]']);

      expect(state.outcome?.action, TileAction.download);
      expect(state.outcome?.error, isNotNull);
      expect(left, ['JMdict [2026-10-03]']);
    });
  });
}
