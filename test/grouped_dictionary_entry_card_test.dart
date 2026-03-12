import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/source_section_label.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:mekuru/shared/widgets/furigana_text.dart';
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';
import 'package:mekuru/shared/widgets/pitch_accent_diagram.dart';

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
    dictionaryId: id,
  );
}

Widget _buildTestApp({
  required AppDatabase db,
  required Widget child,
  double width = 320,
}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
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
              entry: _buildEntry(
                id: 1,
                expression: '飲む',
                reading: 'のむ',
              ),
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
              ),
              PitchAccentResult(
                reading: 'はしる',
                downstepPosition: 0,
                dictionaryName: 'OJAD',
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
}
