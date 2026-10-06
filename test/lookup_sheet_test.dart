import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

DictionaryEntry _buildEntry({
  required int id,
  required String expression,
  required String reading,
  required String glossaries,
}) {
  return DictionaryEntry(
    id: id,
    expression: expression,
    reading: reading,
    entryKind: DictionaryEntryKinds.regular,
    kanjiOnyomi: '',
    kanjiKunyomi: '',
    definitionTags: 'v1',
    rules: 'vt',
    termTags: 'P',
    glossaries: glossaries,
    searchText: '',
    dictionaryId: 1,
  );
}

final _jmdict = DictionaryMeta(
  id: 1,
  name: 'JMdict',
  isEnabled: true,
  dateImported: DateTime(2026, 10, 3),
  sortOrder: 0,
  isHidden: false,
);

class _FakeDictionaryQueryService extends DictionaryQueryService {
  _FakeDictionaryQueryService(super.db, {required this.lookupResultsByTerm});

  final Map<String, List<DictionaryEntryWithSource>> lookupResultsByTerm;
  final List<String> pitchAccentQueries = [];

  @override
  Future<List<DictionaryEntryWithSource>> searchLookupWithSource(
    String primary, [
    String? secondary,
  ]) async {
    return lookupResultsByTerm[primary] ?? const [];
  }

  @override
  Future<Map<String, List<PitchAccentResult>>> searchPitchAccentsBatch(
    Iterable<String> expressions,
  ) async {
    pitchAccentQueries.addAll(expressions);
    return const {};
  }
}

class _FixedTranslationMode extends SentenceTranslationModeNotifier {
  _FixedTranslationMode(this.mode);

  final SentenceTranslationMode mode;

  @override
  SentenceTranslationMode build() => mode;
}

class _HighQualityChosen extends TranslationModelNotifier {
  @override
  TranslationModelChoice build() => TranslationModelChoice.high;
}

/// An installed engine that prefixes "EN:", recording what it translates.
class _FakeTranslationEngine implements TranslationEngine {
  _FakeTranslationEngine({
    this.state = TranslationStatus.installed,
    this.prefix = 'EN:',
  });

  TranslationStatus state;
  final String prefix;
  final translated = <(String, String)>[];
  final downloaded = <String>[];
  bool fails = false;

  @override
  Future<TranslationStatus> status(String target) async => state;

  @override
  Future<void> download(String target) async => downloaded.add(target);

  @override
  Future<String> translate(String text, String target) async {
    translated.add((text, target));
    if (fails) throw StateError('$prefix failed');
    return '$prefix$text';
  }
}

_FakeTranslationEngine _fakeTranslation({
  TranslationStatus state = TranslationStatus.installed,
}) {
  final engine = _FakeTranslationEngine(state: state);
  debugTranslationEngine = engine;
  addTearDown(() => debugTranslationEngine = null);
  return engine;
}

/// Gemma, prefixing "HQ:"; its status also answers whether the model files
/// are there. [download] defaults to one that never finishes.
_FakeTranslationEngine _fakeHighQuality({
  TranslationStatus state = TranslationStatus.installed,
  Future<void> Function(void Function(double fraction) onProgress)? download,
}) {
  final engine = _FakeTranslationEngine(state: state, prefix: 'HQ:');
  debugHighQualityEngine = engine;
  debugGemmaModelOps = (
    installed: () async => engine.state == TranslationStatus.installed,
    download: download ?? (_) => Completer<void>().future,
    delete: () async {},
    hasFiles: () async => false,
    cancel: () => true,
    pending: () async => false,
  );
  addTearDown(() {
    debugHighQualityEngine = null;
    debugGemmaModelOps = null;
  });
  return engine;
}

/// The engine of each `translation.shown` event.
List<Object?> _shownEngines() {
  final engines = <Object?>[];
  usageLogSinkOverride = (message, attributes, {required isWarning}) {
    if (message == 'translation.shown') {
      engines.add(attributes['engine']?.value);
    }
  };
  usageAnalyticsSinkOverride = (name, parameters) {};
  addTearDown(() {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
  });
  return engines;
}

const _notReady = "High quality isn't ready yet; using Standard.";
const _couldNotLoad = "High quality couldn't load; using Standard.";

final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  testWidgets('renders part-of-speech labels in lookup sheet results', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final entry = _buildEntry(
      id: 1,
      expression: '食べる',
      reading: 'たべる',
      glossaries: '["to eat"]',
    );
    final service = _FakeDictionaryQueryService(
      db,
      lookupResultsByTerm: {
        '食べる': [
          DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(service),
          dictionariesProvider.overrideWith((ref) => Stream.value([_jmdict])),
        ],
        child: buildLocalizedTestApp(
          home: const Scaffold(
            body: SizedBox.expand(child: LookupSheet(selectedText: '食べる')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ichidan verb'), findsOneWidget);
    expect(find.text('Transitive verb'), findsOneWidget);
  });

  testWidgets('refreshes pitch accents when the lookup term changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final service = _FakeDictionaryQueryService(
      db,
      lookupResultsByTerm: {
        '食べる': [
          DictionaryEntryWithSource(
            entry: _buildEntry(
              id: 1,
              expression: '食べる',
              reading: 'たべる',
              glossaries: '["to eat"]',
            ),
            dictionaryName: 'JMdict',
          ),
        ],
        '走る': [
          DictionaryEntryWithSource(
            entry: _buildEntry(
              id: 2,
              expression: '走る',
              reading: 'はしる',
              glossaries: '["to run"]',
            ),
            dictionaryName: 'JMdict',
          ),
        ],
      },
    );

    Future<void> pumpLookupSheet(String selectedText) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(service),
            dictionariesProvider.overrideWith((ref) => Stream.value([_jmdict])),
          ],
          child: buildLocalizedTestApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: LookupSheet(selectedText: selectedText),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await pumpLookupSheet('食べる');
    expect(find.text('to eat'), findsOneWidget);
    expect(service.pitchAccentQueries, ['食べる']);

    await pumpLookupSheet('走る');
    expect(find.text('to eat'), findsNothing);
    expect(find.text('to run'), findsOneWidget);
    expect(service.pitchAccentQueries, ['食べる', '走る']);
  });

  for (final showAtTop in [false, true]) {
    testWidgets('keeps the word header pinned while its definitions scroll '
        '(showAtTop: $showAtTop)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Enough senses that the definitions scroll in either sheet.
      final service = _FakeDictionaryQueryService(
        db,
        lookupResultsByTerm: {
          '食べる': [
            for (var i = 1; i <= 30; i++)
              DictionaryEntryWithSource(
                entry: _buildEntry(
                  id: i,
                  expression: '食べる',
                  reading: 'たべる',
                  glossaries: '["sense $i"]',
                ),
                dictionaryName: 'JMdict',
              ),
          ],
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(service),
            dictionariesProvider.overrideWith((ref) => Stream.value([_jmdict])),
          ],
          child: buildLocalizedTestApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: LookupSheet(selectedText: '食べる', showAtTop: showAtTop),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final header = find.byType(GroupedDictionaryEntryHeader);
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      double headerOffset() =>
          tester.getTopLeft(header).dy - tester.getTopLeft(scrollable).dy;
      expect(headerOffset(), 0);

      // The first drag grows the bottom sheet to full height; the second
      // scrolls it.
      for (var i = 0; i < 2; i++) {
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pumpAndSettle();
      }

      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(100),
      );
      expect(find.text('sense 1'), findsNothing);
      expect(headerOffset(), 0);
    });
  }

  group('when the lookup finds nothing', () {
    Future<void> pumpEmptyLookup(
      WidgetTester tester, {
      required List<DictionaryMeta> dictionaries,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(
              _FakeDictionaryQueryService(db, lookupResultsByTerm: const {}),
            ),
            dictionariesProvider.overrideWith(
              (ref) => Stream.value(dictionaries),
            ),
          ],
          child: buildLocalizedTestApp(
            home: const Scaffold(
              body: SizedBox.expand(child: LookupSheet(selectedText: '猫')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('offers the starter pack when no dictionary is installed', (
      tester,
    ) async {
      await pumpEmptyLookup(tester, dictionaries: const []);

      expect(find.text('No dictionaries imported'), findsOneWidget);
      expect(find.text('Install Starter Pack'), findsOneWidget);
    });

    testWidgets('says so plainly when dictionaries are installed', (
      tester,
    ) async {
      await pumpEmptyLookup(tester, dictionaries: [_jmdict]);

      expect(find.text('No results found.'), findsOneWidget);
      expect(find.text('Install Starter Pack'), findsNothing);
    });
  });

  group('Sentence tab', () {
    late AppDatabase db;
    late _FakeDictionaryQueryService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      final entry = _buildEntry(
        id: 1,
        expression: '食べる',
        reading: 'たべる',
        glossaries: '["to eat"]',
      );
      service = _FakeDictionaryQueryService(
        db,
        lookupResultsByTerm: {
          for (final term in ['食べる', '飲む'])
            term: [
              DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
            ],
        },
      );
    });
    tearDown(() => db.close());

    Future<void> pumpSheet(
      WidgetTester tester,
      LookupSheet sheet, {
      SentenceTranslationMode mode = SentenceTranslationMode.shown,
      bool highQuality = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(service),
            dictionariesProvider.overrideWith((ref) => Stream.value([_jmdict])),
            sentenceTranslationModeProvider.overrideWith(
              () => _FixedTranslationMode(mode),
            ),
            if (highQuality)
              translationModelProvider.overrideWith(_HighQualityChosen.new),
          ],
          child: buildLocalizedTestApp(
            home: Scaffold(body: SizedBox.expand(child: sheet)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openSentenceTab(WidgetTester tester) async {
      await tester.tap(find.text('Sentence'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('has no tabs without a sentence', (tester) async {
      _fakeTranslation();
      await pumpSheet(tester, const LookupSheet(selectedText: '食べる'));

      expect(find.text('Sentence'), findsNothing);
      expect(find.byType(GroupedDictionaryEntryHeader), findsOneWidget);
    });

    testWidgets('has no tabs when the setting is off', (tester) async {
      _fakeTranslation();
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '朝ご飯を食べる。'),
        mode: SentenceTranslationMode.off,
      );

      expect(find.text('Sentence'), findsNothing);
    });

    testWidgets('shows the sentence and its translation', (tester) async {
      final engine = _fakeTranslation();
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: 'パンを食べる。'),
      );
      expect(find.byType(GroupedDictionaryEntryHeader), findsOneWidget);

      await openSentenceTab(tester);

      expect(find.byType(GroupedDictionaryEntryHeader), findsNothing);
      expect(find.text('パンを食べる。', findRichText: true), findsOneWidget);
      expect(find.text('EN:パンを食べる。'), findsOneWidget);
      expect(find.text('Machine translation'), findsOneWidget);
      expect(engine.translated, [('パンを食べる。', 'en')]);
    });

    testWidgets('switching tabs keeps both instead of starting over', (
      tester,
    ) async {
      final engine = _fakeTranslation();
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '豆を食べる。'),
      );
      await openSentenceTab(tester);
      await tester.tap(find.text('Dictionary'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(GroupedDictionaryEntryHeader), findsOneWidget);

      await openSentenceTab(tester);
      expect(find.text('EN:豆を食べる。'), findsOneWidget);
      expect(engine.translated, hasLength(1));
    });

    testWidgets('hides the translation until tapped', (tester) async {
      _fakeTranslation();
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '魚を食べる。'),
        mode: SentenceTranslationMode.hidden,
      );
      await openSentenceTab(tester);

      expect(find.text('EN:魚を食べる。'), findsNothing);
      await tester.tap(find.text('Tap to show translation'));
      await tester.pump();
      expect(find.text('EN:魚を食べる。'), findsOneWidget);
    });

    testWidgets('offers the download before the model is installed', (
      tester,
    ) async {
      final engine = _fakeTranslation(state: TranslationStatus.needsDownload);
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '肉を食べる。'),
      );
      await openSentenceTab(tester);

      expect(
        find.text(
          'Download Japanese translation (55 MB) to translate sentences '
          'offline.',
        ),
        findsOneWidget,
      );
      expect(find.text('Download'), findsOneWidget);
      expect(engine.translated, isEmpty);
    });

    testWidgets('a phone low on memory is warned before the download', (
      tester,
    ) async {
      final engine = _fakeTranslation(state: TranslationStatus.needsDownload);
      debugDeviceLowOnMemory = true;
      addTearDown(() => debugDeviceLowOnMemory = null);
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '鳥を食べる。'),
      );
      await openSentenceTab(tester);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('This phone may struggle'), findsOneWidget);
      expect(engine.downloaded, isEmpty);

      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(engine.downloaded, isEmpty);
    });

    testWidgets('a new word opens on the Dictionary tab', (tester) async {
      _fakeTranslation();
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '米を食べる。'),
      );
      await openSentenceTab(tester);
      expect(find.byType(GroupedDictionaryEntryHeader), findsNothing);

      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '飲む', sentenceContext: '水を飲む。'),
      );

      expect(find.byType(GroupedDictionaryEntryHeader), findsOneWidget);
    });

    testWidgets('only an editable sheet lets the sentence be edited', (
      tester,
    ) async {
      _fakeTranslation();
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '卵を食べる。'),
      );
      await openSentenceTab(tester);

      expect(find.byTooltip('Edit sentence'), findsNothing);
    });

    testWidgets('an edited sentence is translated and saved with the word', (
      tester,
    ) async {
      final engine = _fakeTranslation();
      await pumpSheet(
        tester,
        const LookupSheet(
          selectedText: '食べる',
          sentenceContext: '卯を食べる。',
          editable: true,
        ),
      );
      await openSentenceTab(tester);

      await tester.tap(find.byTooltip('Edit sentence'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '卵を食べる！');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('EN:卵を食べる！'), findsOneWidget);
      expect(engine.translated.map((t) => t.$1), ['卯を食べる。', '卵を食べる！']);

      await tester.tap(find.text('Dictionary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<GroupedDictionaryEntryHeader>(
              find.byType(GroupedDictionaryEntryHeader),
            )
            .sentenceContext,
        '卵を食べる！',
      );
    });

    Future<void> startGemmaDownload(WidgetTester tester) async {
      unawaited(
        ProviderScope.containerOf(
          tester.element(find.byType(LookupSheet)),
        ).read(gemmaDownloadProvider.notifier).start(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('translates with High quality when chosen and ready', (
      tester,
    ) async {
      final engines = _shownEngines();
      final standard = _fakeTranslation();
      _fakeHighQuality();
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: 'パンを食べる。'),
        highQuality: true,
      );
      await openSentenceTab(tester);
      // Gemma's first disk check reports it installed and reloads the tab.
      await tester.pump();

      expect(find.text('HQ:パンを食べる。'), findsOneWidget);
      expect(find.text(_notReady), findsNothing);
      expect(standard.translated, isEmpty);
      expect(engines, ['gemma']);
    }, variant: _android);

    testWidgets('a High choice without its model goes back to Standard', (
      tester,
    ) async {
      final engines = _shownEngines();
      _fakeTranslation();
      _fakeHighQuality(state: TranslationStatus.needsDownload);
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '粥を食べる。'),
        highQuality: true,
      );
      await openSentenceTab(tester);
      // Gemma's first disk check finds no model, which drops the choice and
      // reloads the tab.
      await tester.pump();

      expect(find.text('EN:粥を食べる。'), findsOneWidget);
      expect(find.text(_notReady), findsNothing);
      expect(engines, everyElement('mozilla'));
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(LookupSheet)),
        ).read(translationModelProvider),
        TranslationModelChoice.standard,
      );
    }, variant: _android);

    testWidgets('says so when an installed High-quality model cannot load', (
      tester,
    ) async {
      _fakeTranslation();
      _fakeHighQuality().fails = true;
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '鮭を食べる。'),
        highQuality: true,
      );
      await openSentenceTab(tester);
      // Gemma's first disk check reports it installed and reloads the tab.
      await tester.pump();

      expect(find.text('EN:鮭を食べる。'), findsOneWidget);
      expect(find.text(_couldNotLoad), findsOneWidget);
      expect(find.text(_notReady), findsNothing);
    }, variant: _android);

    testWidgets('switches to High quality when its download finishes', (
      tester,
    ) async {
      _fakeTranslation();
      late final _FakeTranslationEngine high;
      high = _fakeHighQuality(
        state: TranslationStatus.needsDownload,
        download: (_) async => high.state = TranslationStatus.installed,
      );
      // Standard while the model downloads: the download chooses High.
      await pumpSheet(
        tester,
        const LookupSheet(selectedText: '食べる', sentenceContext: '餅を食べる。'),
      );
      await openSentenceTab(tester);
      expect(find.text('EN:餅を食べる。'), findsOneWidget);

      await startGemmaDownload(tester);

      expect(find.text('HQ:餅を食べる。'), findsOneWidget);
      expect(find.text(_notReady), findsNothing);
    }, variant: _android);
  });
}
