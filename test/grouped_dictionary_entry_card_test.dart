import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/ankidroid/data/models/ankidroid_config.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/anki_card_creation_screen.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/source_section_label.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:mekuru/shared/widgets/furigana_text.dart';
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';
import 'package:mekuru/shared/widgets/pitch_accent_diagram.dart';

import 'features/ankidroid/ankidroid_test_doubles.dart';
import 'shared/yomitan_glossary_fixtures.dart';
import 'test_app.dart';

DictionaryEntry _buildEntry({
  required int id,
  required String expression,
  required String reading,
  String entryKind = DictionaryEntryKinds.regular,
  String kanjiOnyomi = '',
  String kanjiKunyomi = '',
  String definitionTags = '',
  String rules = '',
  String termTags = '',
  String glossaries = '["definition"]',
  int? dictionaryId,
}) {
  return DictionaryEntry(
    id: id,
    expression: expression,
    reading: reading,
    entryKind: entryKind,
    kanjiOnyomi: kanjiOnyomi,
    kanjiKunyomi: kanjiKunyomi,
    definitionTags: definitionTags,
    rules: rules,
    termTags: termTags,
    glossaries: glossaries,
    searchText: '',
    dictionaryId: dictionaryId ?? id,
  );
}

Widget _buildTestApp({
  required AppDatabase db,
  required Widget child,
  double width = 320,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db), ...overrides],
    child: buildLocalizedTestApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('regular entries still render furigana', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        db: db,
        width: 520,
        child: GroupedDictionaryEntryCard(
          entries: [
            DictionaryEntryWithSource(
              entry: _buildEntry(id: 1, expression: '食べる', reading: 'たべる'),
              dictionaryName: 'JMdict',
              frequencyRank: 3000,
            ),
          ],
          pitchAccents: const [],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FuriganaText), findsOneWidget);
    expect(find.textContaining('Onyomi:'), findsNothing);
    expect(find.textContaining('Kunyomi:'), findsNothing);
    expect(find.text('Very Common'), findsOneWidget);
  });

  testWidgets('renders part-of-speech chips when tags are present', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        db: db,
        width: 520,
        child: GroupedDictionaryEntryCard(
          entries: [
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: 1,
                expression: '食べる',
                reading: 'たべる',
                rules: 'v1 vt',
                termTags: 'P',
              ),
              dictionaryName: 'JMdict',
            ),
          ],
          pitchAccents: const [],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Ichidan verb'), findsOneWidget);
    expect(find.text('Transitive verb'), findsOneWidget);
    expect(find.text('P'), findsNothing);
  });

  testWidgets('omits part-of-speech chips when tags are absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        db: db,
        width: 420,
        child: GroupedDictionaryEntryCard(
          entries: [
            DictionaryEntryWithSource(
              entry: _buildEntry(id: 1, expression: '飲む', reading: 'のむ'),
              dictionaryName: 'JMdict',
            ),
          ],
          pitchAccents: const [],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Ichidan verb'), findsNothing);
    expect(find.text('Noun'), findsNothing);
  });

  testWidgets('kanji entries render labeled reading lines without furigana', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        db: db,
        width: 140,
        child: GroupedDictionaryEntryCard(
          entries: [
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: 1,
                expression: '日',
                reading: 'ニチ ジツ ひ か',
                entryKind: DictionaryEntryKinds.kanji,
                kanjiOnyomi: '["ニチ","ジツ"]',
                kanjiKunyomi: '["ひ","か"]',
              ),
              dictionaryName: 'KANJIDIC English',
              frequencyRank: 3000,
            ),
          ],
          pitchAccents: const [],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FuriganaText), findsNothing);
    expect(find.textContaining('Onyomi:'), findsOneWidget);
    expect(find.textContaining('Kunyomi:'), findsOneWidget);
    expect(find.text('Very Common'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'definition sections use bottom-aligned source footers once per dictionary',
    (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          db: db,
          child: GroupedDictionaryEntryCard(
            entries: [
              DictionaryEntryWithSource(
                entry: _buildEntry(
                  id: 1,
                  expression: '日',
                  reading: 'ニチ ジツ ひ か',
                  entryKind: DictionaryEntryKinds.kanji,
                  kanjiOnyomi: '["ニチ","ジツ"]',
                  kanjiKunyomi: '["ひ","か"]',
                  glossaries: '["sun c"]',
                ),
                dictionaryName: 'Dict C',
              ),
              DictionaryEntryWithSource(
                entry: _buildEntry(
                  id: 2,
                  expression: '日',
                  reading: 'ニチ ジツ ひ か',
                  entryKind: DictionaryEntryKinds.kanji,
                  kanjiOnyomi: '["ニチ","ジツ"]',
                  kanjiKunyomi: '["ひ","か"]',
                  glossaries: '["sun a"]',
                ),
                dictionaryName: 'Dict A',
              ),
              DictionaryEntryWithSource(
                entry: _buildEntry(
                  id: 3,
                  expression: '日',
                  reading: 'ニチ ジツ ひ か',
                  entryKind: DictionaryEntryKinds.kanji,
                  kanjiOnyomi: '["ニチ","ジツ"]',
                  kanjiKunyomi: '["ひ","か"]',
                  glossaries: '["sun a second"]',
                  dictionaryId: 2,
                ),
                dictionaryName: 'Dict A',
              ),
              DictionaryEntryWithSource(
                entry: _buildEntry(
                  id: 4,
                  expression: '日',
                  reading: 'ニチ ジツ ひ か',
                  entryKind: DictionaryEntryKinds.kanji,
                  kanjiOnyomi: '["ニチ","ジツ"]',
                  kanjiKunyomi: '["ひ","か"]',
                  glossaries: '["sun b"]',
                ),
                dictionaryName: 'Dict B',
              ),
            ],
            pitchAccents: const [],
          ),
        ),
      );

      await tester.pumpAndSettle();

      final sourceLabels = tester
          .widgetList<SourceSectionLabel>(find.byType(SourceSectionLabel))
          .map((widget) => widget.label)
          .toList();

      expect(sourceLabels, ['Dict C', 'Dict A', 'Dict B']);
      expect(find.text('Dict C'), findsOneWidget);
      expect(find.text('Dict A'), findsOneWidget);
      expect(find.text('Dict B'), findsOneWidget);
      expect(find.text('1. sun a'), findsOneWidget);
      expect(find.text('2. sun a second'), findsOneWidget);

      final textWidgets = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();

      expect(
        textWidgets.indexOf('sun c'),
        lessThan(textWidgets.indexOf('Dict C')),
      );
      expect(
        textWidgets.indexOf('2. sun a second'),
        lessThan(textWidgets.indexOf('Dict A')),
      );
      expect(
        textWidgets.indexOf('sun b'),
        lessThan(textWidgets.indexOf('Dict B')),
      );
    },
  );

  testWidgets(
    'pitch accent sections use the same bottom-aligned source footers',
    (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          db: db,
          child: GroupedDictionaryEntryCard(
            entries: [
              DictionaryEntryWithSource(
                entry: _buildEntry(id: 1, expression: '走る', reading: 'はしる'),
                dictionaryName: 'JMdict',
              ),
            ],
            pitchAccents: const [
              PitchAccentResult(
                reading: 'はしる',
                downstepPosition: 2,
                dictionaryName: 'NHK',
                dictionaryId: 2,
              ),
              PitchAccentResult(
                reading: 'はしる',
                downstepPosition: 0,
                dictionaryName: 'OJAD',
                dictionaryId: 3,
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      final sourceLabels = tester
          .widgetList<SourceSectionLabel>(find.byType(SourceSectionLabel))
          .map((widget) => widget.label)
          .toList();

      expect(sourceLabels, ['NHK', 'OJAD', 'JMdict']);
      expect(find.byType(PitchAccentDiagram), findsNWidgets(2));
      expect(find.text('NHK'), findsOneWidget);
      expect(find.text('OJAD'), findsOneWidget);
      expect(find.text('JMdict'), findsOneWidget);
    },
  );

  testWidgets('two dictionaries with the same name keep their own sections', (
    tester,
  ) async {
    // Shown names drop the version, so two revisions of a dictionary
    // installed side by side share one.
    await tester.pumpWidget(
      _buildTestApp(
        db: db,
        child: GroupedDictionaryEntryCard(
          entries: [
            DictionaryEntryWithSource(
              entry: _buildEntry(id: 1, expression: '走る', reading: 'はしる'),
              dictionaryName: 'JMdict',
            ),
            DictionaryEntryWithSource(
              entry: _buildEntry(id: 2, expression: '走る', reading: 'はしる'),
              dictionaryName: 'JMdict',
            ),
          ],
          pitchAccents: const [
            PitchAccentResult(
              reading: 'はしる',
              downstepPosition: 2,
              dictionaryName: 'NHK',
              dictionaryId: 3,
            ),
            PitchAccentResult(
              reading: 'はしる',
              downstepPosition: 2,
              dictionaryName: 'NHK',
              dictionaryId: 4,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceLabels = tester
        .widgetList<SourceSectionLabel>(find.byType(SourceSectionLabel))
        .map((widget) => widget.label)
        .toList();
    expect(sourceLabels, ['NHK', 'NHK', 'JMdict', 'JMdict']);
  });

  testWidgets('a structured-content row is laid out, not flattened', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        db: db,
        width: 400,
        child: GroupedDictionaryEntryCard(
          entries: [
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: 1,
                expression: '食べる',
                reading: 'たべる',
                glossaries: jsonEncode([jitendexTaberu]),
              ),
              dictionaryName: 'Jitendex.org [2026-10-03]',
            ),
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: 2,
                expression: '食べる',
                reading: 'たべる',
                glossaries: '["to eat (plain)"]',
              ),
              dictionaryName: 'Plain Dict',
            ),
          ],
          pitchAccents: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1-dan'), findsOneWidget);
    expect(find.text('①'), findsOneWidget);
    expect(find.text('くだ'), findsOneWidget);
    expect(find.textContaining('▸', findRichText: true), findsNothing);
    expect(find.text('to eat (plain)'), findsOneWidget);
  });

  testWidgets('saving a Jitendex redirect saves the definitions it points to', (
    tester,
  ) async {
    final repository = DictionaryRepository(db);
    final dictionaryId = await repository.insertDictionary('Jitendex.org');
    const target = '["Minister of Labour"]';
    await repository.batchInsertEntries([
      for (final (reading, glossaries) in [
        ('ろうどうしょう', target),
        // Same spelling, another reading: not the one the link names.
        ('ろうどうそう', '["wrong reading"]'),
      ])
        DictionaryEntriesCompanion.insert(
          expression: '労働相',
          reading: Value(reading),
          glossaries: glossaries,
          dictionaryId: dictionaryId,
        ),
    ]);

    await tester.pumpWidget(
      _buildTestApp(
        db: db,
        width: 400,
        child: GroupedDictionaryEntryCard(
          entries: [
            DictionaryEntryWithSource(
              entry: _buildEntry(
                id: 10,
                expression: '労働大臣',
                reading: 'ろうどうだいじん',
                glossaries: jsonEncode([stored(jitendexRedirect)]),
                dictionaryId: dictionaryId,
              ),
              dictionaryName: 'Jitendex',
            ),
          ],
          pitchAccents: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save to Vocabulary'));
    await tester.pumpAndSettle();

    final saved = await db.select(db.savedWords).getSingle();
    expect(saved.expression, '労働大臣');
    expect(saved.glossaries, target);
  });

  testWidgets(
    'the Anki button waits for the translation, then opens one card',
    (tester) async {
      final translation = Completer<String>();
      debugTranslationEngine = _PendingTranslation(translation.future);
      addTearDown(() => debugTranslationEngine = null);
      await tester.pumpWidget(
        _buildTestApp(
          db: db,
          width: 400,
          overrides: [
            ankidroidAvailableProvider.overrideWithValue(true),
            ankidroidServiceProvider.overrideWithValue(FakeAnkidroidService()),
            ankidroidConfigProvider.overrideWith(
              () => TestAnkidroidConfigNotifier(
                const AnkidroidConfig(
                  modelId: 5,
                  modelName: 'Basic',
                  deckId: 1,
                  deckName: 'Default',
                  fieldMapping: {
                    'Front': 'expression',
                    'Back': 'sentence_translation',
                  },
                ),
              ),
            ),
          ],
          child: GroupedDictionaryEntryCard(
            entries: [
              DictionaryEntryWithSource(
                entry: _buildEntry(id: 1, expression: '猫', reading: 'ねこ'),
                dictionaryName: 'JMdict',
              ),
            ],
            pitchAccents: const [],
            sentenceContext: '猫が窓の外で鳴いた。',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final anki = find.byIcon(Icons.electric_bolt_outlined);
      await tester.tap(anki);
      await tester.pump();
      // Busy until the translation arrives, so another tap can't open a
      // second card screen.
      expect(anki, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      translation.complete('The cat meowed outside the window.');
      await tester.pumpAndSettle();
      expect(find.byType(AnkiCardCreationScreen), findsOneWidget);
    },
  );
}

/// An installed engine whose translation arrives when the test says so.
class _PendingTranslation implements TranslationEngine {
  _PendingTranslation(this.result);

  final Future<String> result;

  @override
  Future<TranslationStatus> status(String target) async =>
      TranslationStatus.installed;

  @override
  Future<void> download(String target) async {}

  @override
  Future<String> translate(String text, String target) => result;
}
