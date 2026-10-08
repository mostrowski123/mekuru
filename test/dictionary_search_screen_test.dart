import 'dart:async';

import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';
import 'package:mekuru/shared/widgets/structured_glossary_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/fake_download_notifiers.dart';
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

class _FakeDictionaryQueryService extends DictionaryQueryService {
  _FakeDictionaryQueryService(super.db, {required this.resultsByTerm});

  final Map<String, List<DictionaryEntryWithSource>> resultsByTerm;
  final List<List<String>> pitchAccentBatchQueries = [];
  final Map<String, Completer<void>> gates = {};
  bool failSearch = false;
  bool failPitchAccents = false;

  @override
  Future<List<DictionaryEntryWithSource>> fuzzySearchWithSource(
    String term,
  ) async {
    if (failSearch) throw StateError('search unavailable');
    await gates[term]?.future;
    return resultsByTerm[term] ?? const [];
  }

  @override
  Future<List<PitchAccentResult>> searchPitchAccents(String term) async {
    return const [];
  }

  @override
  Future<Map<String, List<PitchAccentResult>>> searchPitchAccentsBatch(
    Iterable<String> expressions,
  ) async {
    if (failPitchAccents) throw StateError('pitch accents unavailable');
    final batch = expressions.toList(growable: false);
    pitchAccentBatchQueries.add(batch);
    return {for (final expression in batch) expression: const []};
  }
}

DictionaryMeta _enabledDictionary() => DictionaryMeta(
  id: 1,
  name: 'JMdict',
  isEnabled: true,
  dateImported: DateTime(2026, 3, 12),
  sortOrder: 0,
  isHidden: false,
);

_FakeDictionaryQueryService _buildService(AppDatabase db) {
  final entry = _buildEntry(
    id: 1,
    expression: '食べる',
    reading: 'たべる',
    glossaries: '["to eat"]',
  );
  return _FakeDictionaryQueryService(
    db,
    resultsByTerm: {
      '食べる': [
        DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
      ],
    },
  );
}

/// Pumps the search screen over [service] with one enabled dictionary.
Future<void> _pumpSearchScreen(
  WidgetTester tester,
  AppDatabase db,
  _FakeDictionaryQueryService service, {
  String? initialQuery,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dictionaryQueryServiceProvider.overrideWithValue(service),
        dictionariesProvider.overrideWith(
          (ref) => Stream.value([_enabledDictionary()]),
        ),
      ],
      child: buildLocalizedTestApp(
        home: DictionarySearchScreen(initialQuery: initialQuery),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('definitions far below the screen are built only once scrolled '
      'near', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeDictionaryQueryService(
      db,
      resultsByTerm: {
        'many': [
          for (var i = 0; i < 40; i++)
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: i + 1,
                expression: '語$i',
                reading: 'ご$i',
                glossaries: '["word $i"]',
              ),
              dictionaryName: 'JMdict',
            ),
        ],
      },
    );

    await _pumpSearchScreen(tester, db, service, initialQuery: 'many');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final built = find
        .byType(StructuredGlossaryView, skipOffstage: false)
        .evaluate()
        .length;
    expect(built, greaterThan(0));
    expect(built, lessThan(40));
  });

  testWidgets('tapping outside the search field dismisses the keyboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeDictionaryQueryService(db, resultsByTerm: const {});

    await _pumpSearchScreen(tester, db, service);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final focusNode = tester.widget<TextField>(find.byType(TextField)).focusNode!;
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(const Offset(400, 500));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('shows guidance when all imported dictionaries are disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final dictionaries = [
      DictionaryMeta(
        id: 1,
        name: 'JMdict English',
        isEnabled: false,
        dateImported: DateTime(2026, 3, 8),
        sortOrder: 1,
        isHidden: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionariesProvider.overrideWith(
            (ref) => Stream.value(dictionaries),
          ),
        ],
        child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Your dictionaries are turned off'), findsOneWidget);
    expect(find.text('Enable dictionaries'), findsOneWidget);
    expect(find.text('Starter pack'), findsOneWidget);
  });

  testWidgets(
    'the starter pack button installs in one tap and opens Downloads',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      mockWifiConnected(true);
      final started = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: fakeDownloadNotifierOverrides(started),
          child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recommended starter pack'));
      await tester.pumpAndSettle();

      expect(started, unorderedEquals(<String>['catalog:jitendex', 'jpdb']));
      expect(find.byType(DownloadsScreen), findsOneWidget);
    },
  );

  testWidgets('renders part-of-speech labels in dictionary search results', (
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
      resultsByTerm: {
        '食べる': [
          DictionaryEntryWithSource(entry: entry, dictionaryName: 'JMdict'),
        ],
      },
    );

    final dictionaries = [
      DictionaryMeta(
        id: 1,
        name: 'JMdict',
        isEnabled: true,
        dateImported: DateTime(2026, 3, 12),
        sortOrder: 0,
        isHidden: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(service),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value(dictionaries),
          ),
        ],
        child: buildLocalizedTestApp(
          home: const DictionarySearchScreen(initialQuery: '食べる'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ichidan verb'), findsOneWidget);
    expect(find.text('Transitive verb'), findsOneWidget);
  });

  testWidgets('keeps each top-level word header sticky until the next word', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final firstGroup = [
      for (var i = 0; i < 18; i++)
        DictionaryEntryWithSource(
          entry: _buildEntry(
            id: i + 1,
            expression: '食べる',
            reading: 'たべる',
            glossaries: '["definition ${i + 1}"]',
          ),
          dictionaryName: 'JMdict',
        ),
    ];
    final secondGroup = [
      for (var i = 0; i < 20; i++)
        DictionaryEntryWithSource(
          entry: _buildEntry(
            id: 200 + i,
            expression: '走る',
            reading: 'はしる',
            glossaries: '["run definition ${i + 1}"]',
          ),
          dictionaryName: 'JMdict',
        ),
    ];

    final service = _FakeDictionaryQueryService(
      db,
      resultsByTerm: {
        'sticky': [...firstGroup, ...secondGroup],
      },
    );

    final dictionaries = [
      DictionaryMeta(
        id: 1,
        name: 'JMdict',
        isEnabled: true,
        dateImported: DateTime(2026, 3, 12),
        sortOrder: 0,
        isHidden: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(service),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value(dictionaries),
          ),
        ],
        child: buildLocalizedTestApp(
          home: const DictionarySearchScreen(initialQuery: 'sticky'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final resultsFinder = find.byType(CustomScrollView);
    final firstHeaderFinder = find.byWidgetPredicate(
      (widget) =>
          widget is GroupedDictionaryEntryHeader &&
          widget.entries.first.entry.expression == '食べる',
    );
    final secondHeaderFinder = find.byWidgetPredicate(
      (widget) =>
          widget is GroupedDictionaryEntryHeader &&
          widget.entries.first.entry.expression == '走る',
    );
    final pinnedTop = tester.getTopLeft(firstHeaderFinder).dy;

    await tester.drag(resultsFinder, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(firstHeaderFinder, findsOneWidget);
    expect(tester.getTopLeft(firstHeaderFinder).dy, closeTo(pinnedTop, 1.0));

    await tester.dragUntilVisible(
      secondHeaderFinder,
      resultsFinder,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    for (
      var i = 0;
      i < 10 && tester.getTopLeft(secondHeaderFinder).dy > pinnedTop + 1;
      i++
    ) {
      await tester.drag(resultsFinder, const Offset(0, -80));
      await tester.pumpAndSettle();
    }

    expect(secondHeaderFinder, findsOneWidget);
    expect(tester.getTopLeft(secondHeaderFinder).dy, closeTo(pinnedTop, 1.0));
    if (firstHeaderFinder.evaluate().isNotEmpty) {
      expect(tester.getTopLeft(firstHeaderFinder).dy, lessThan(pinnedTop));
    }
  });

  testWidgets(
    'refetches batched pitch accents when the visible result changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final service = _FakeDictionaryQueryService(
        db,
        resultsByTerm: {
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

      final dictionaries = [
        DictionaryMeta(
          id: 1,
          name: 'JMdict',
          isEnabled: true,
          dateImported: DateTime(2026, 3, 12),
          sortOrder: 0,
          isHidden: false,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(service),
            dictionariesProvider.overrideWith(
              (ref) => Stream.value(dictionaries),
            ),
          ],
          child: buildLocalizedTestApp(
            home: const DictionarySearchScreen(initialQuery: '食べる'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('to eat'), findsOneWidget);
      expect(
        service.pitchAccentBatchQueries.any(
          (batch) => batch.length == 1 && batch.first == '食べる',
        ),
        isTrue,
      );

      await tester.enterText(find.byType(TextField), '走る');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('to eat'), findsNothing);
      expect(find.text('to run'), findsOneWidget);
      expect(
        service.pitchAccentBatchQueries.any(
          (batch) => batch.length == 1 && batch.first == '走る',
        ),
        isTrue,
      );
    },
  );

  group('recent search history commit behavior', () {
    testWidgets(
      'typing characters does not save partial keystrokes to history',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(_buildService(db)),
            dictionariesProvider.overrideWith(
              (ref) => Stream.value([_enabledDictionary()]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextField), '食べる');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Results rendered, but the screen is still mounted — no commit yet.
        expect(find.text('to eat'), findsOneWidget);
        expect(container.read(searchHistoryProvider), isEmpty);
      },
    );

    testWidgets('disposing the screen with shown results commits the query', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(_buildService(db)),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value([_enabledDictionary()]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '食べる');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(container.read(searchHistoryProvider), isEmpty);

      // Replace the tree to trigger DictionarySearchScreen.dispose().
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(home: const SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(searchHistoryProvider), ['食べる']);
    });

    testWidgets(
      'reader-initiated initialQuery auto-saves once results come back',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(_buildService(db)),
            dictionariesProvider.overrideWith(
              (ref) => Stream.value([_enabledDictionary()]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: buildLocalizedTestApp(
              home: const DictionarySearchScreen(initialQuery: '食べる'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Auto-commit fires as soon as the initial-query search resolves;
        // no further user interaction required.
        expect(find.text('to eat'), findsOneWidget);
        expect(container.read(searchHistoryProvider), ['食べる']);
      },
    );

    testWidgets('pausing for 1.5s after typing commits the query to history', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(_buildService(db)),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value([_enabledDictionary()]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '食べる');
      // 300ms search debounce + a beat to flush async search results.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(container.read(searchHistoryProvider), isEmpty);

      // Remaining time until the 1.5s history debounce fires.
      await tester.pump(const Duration(milliseconds: 1200));

      expect(container.read(searchHistoryProvider), ['食べる']);
    });

    testWidgets('clearing the field cancels the pending 1.5s history commit', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(_buildService(db)),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value([_enabledDictionary()]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(home: const DictionarySearchScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '食べる');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      // Tap the clear (X) icon before the 1.5s timer fires.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump(const Duration(milliseconds: 1600));

      expect(container.read(searchHistoryProvider), isEmpty);
    });

    testWidgets('app backgrounding commits the current search to history', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(_buildService(db)),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value([_enabledDictionary()]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final screenKey = GlobalKey<DictionarySearchScreenState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            home: DictionarySearchScreen(key: screenKey),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '食べる');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(container.read(searchHistoryProvider), isEmpty);

      screenKey.currentState!.handleLifecycleStateChanged(
        AppLifecycleState.paused,
      );

      expect(container.read(searchHistoryProvider), ['食べる']);
    });

    testWidgets('commitHistoryIfNeeded saves when the parent switches tabs', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryQueryServiceProvider.overrideWithValue(_buildService(db)),
          dictionariesProvider.overrideWith(
            (ref) => Stream.value([_enabledDictionary()]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final screenKey = GlobalKey<DictionarySearchScreenState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: buildLocalizedTestApp(
            home: DictionarySearchScreen(key: screenKey),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '食べる');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(container.read(searchHistoryProvider), isEmpty);

      screenKey.currentState!.commitHistoryIfNeeded();

      expect(container.read(searchHistoryProvider), ['食べる']);
    });
  });

  testWidgets('a new query starts at the top of the results', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    List<DictionaryEntryWithSource> manyWords(String prefix, int firstId) => [
      for (var i = 0; i < 30; i++)
        DictionaryEntryWithSource(
          entry: _buildEntry(
            id: firstId + i,
            expression: '$prefix$i',
            reading: '$prefix$i',
            glossaries: '["$prefix definition $i"]',
          ),
          dictionaryName: 'JMdict',
        ),
    ];
    final service = _FakeDictionaryQueryService(
      db,
      resultsByTerm: {
        'first': manyWords('一', 1),
        'second': manyWords('二', 100),
      },
    );
    await _pumpSearchScreen(tester, db, service, initialQuery: 'first');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final resultsFinder = find.byType(CustomScrollView);
    double scrollOffset() => tester
        .state<ScrollableState>(
          find.descendant(of: resultsFinder, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;

    await tester.drag(resultsFinder, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(scrollOffset(), greaterThan(0));

    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(scrollOffset(), 0);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GroupedDictionaryEntryHeader &&
            widget.entries.first.entry.expression == '二0',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a search that finishes after the field changed is discarded', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final service = _FakeDictionaryQueryService(
      db,
      resultsByTerm: {
        'たべる': [
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
        'ねこ': [
          DictionaryEntryWithSource(
            entry: _buildEntry(
              id: 2,
              expression: '猫',
              reading: 'ねこ',
              glossaries: '["cat"]',
            ),
            dictionaryName: 'JMdict',
          ),
        ],
      },
    );
    final slowSearch = Completer<void>();
    service.gates['たべる'] = slowSearch;
    await _pumpSearchScreen(tester, db, service);

    // The first search starts and blocks; the field changes while the
    // second search is still debouncing.
    await tester.enterText(find.byType(TextField), 'たべる');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'ねこ');
    await tester.pump(const Duration(milliseconds: 100));

    slowSearch.complete();
    await tester.pump();
    expect(find.text('to eat'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('cat'), findsOneWidget);
    expect(find.text('to eat'), findsNothing);
  });

  group('search failures', () {
    late List<String> failures;

    setUp(() {
      failures = [];
      usageLogSinkOverride = (message, attributes, {required isWarning}) {
        if (isWarning) failures.add(message);
      };
    });

    tearDown(() {
      usageLogSinkOverride = null;
    });

    Future<_FakeDictionaryQueryService> pumpScreen(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _buildService(db);
      await _pumpSearchScreen(tester, db, service);
      return service;
    }

    Future<void> search(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), '食べる');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('word results survive a pitch-accent failure', (tester) async {
      final service = await pumpScreen(tester);
      service.failPitchAccents = true;
      await search(tester);
      expect(find.text('to eat'), findsOneWidget);
      expect(failures, contains('dictionary.pitch_accents_failed'));
    });

    testWidgets('a failed search is reported', (tester) async {
      final service = await pumpScreen(tester);
      service.failSearch = true;
      await search(tester);
      expect(failures, contains('dictionary.search_failed'));
    });

    // MEKURU-1Z: a search can wait seconds on a database busy importing a
    // dictionary, and the user may leave before it answers.
    testWidgets('leaving while a search runs ends it quietly', (tester) async {
      final service = await pumpScreen(tester);
      final slowSearch = Completer<void>();
      service.gates['食べる'] = slowSearch;
      await tester.enterText(find.byType(TextField), '食べる');
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(const SizedBox());
      slowSearch.complete();
      await tester.pumpAndSettle();

      expect(failures, isEmpty);
      // No follow-up query for a screen that is gone.
      expect(service.pitchAccentBatchQueries, isEmpty);
    });
  });

  testWidgets('in Low RAM mode, a word tapped at depth 3 replaces the screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _buildService(db);

    Future<void> tapWordAtDepth(int depth, {required bool lowRamMode}) async {
      await tester.pumpWidget(
        ProviderScope(
          // A new app each time, so no screen is left over.
          key: UniqueKey(),
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryQueryServiceProvider.overrideWithValue(service),
            dictionariesProvider.overrideWith(
              (ref) => Stream.value([_enabledDictionary()]),
            ),
            lowRamModeProvider.overrideWithBuild((ref, _) => lowRamMode),
          ],
          child: buildLocalizedTestApp(
            home: DictionarySearchScreen(initialQuery: '食べる', depth: depth),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      tester
          .widget<GroupedDictionaryEntryHeader>(
            find.byType(GroupedDictionaryEntryHeader),
          )
          .onWordTap!('食べる');
      await tester.pumpAndSettle();
    }

    Finder screenAtDepth(int depth) => find.byWidgetPredicate(
      (widget) => widget is DictionarySearchScreen && widget.depth == depth,
      skipOffstage: false,
    );

    await tapWordAtDepth(3, lowRamMode: true);
    expect(screenAtDepth(3), findsNothing);
    expect(screenAtDepth(4), findsOneWidget);

    // Not as deep, or with the mode off, the word opens on top.
    await tapWordAtDepth(2, lowRamMode: true);
    expect(screenAtDepth(2), findsOneWidget);
    expect(screenAtDepth(3), findsOneWidget);

    await tapWordAtDepth(3, lowRamMode: false);
    expect(screenAtDepth(3), findsOneWidget);
    expect(screenAtDepth(4), findsOneWidget);
  });
}
