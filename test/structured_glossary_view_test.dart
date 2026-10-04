import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/hit_testable_rich_text.dart';
import 'package:mekuru/shared/widgets/structured_glossary_view.dart';

import 'shared/test_database.dart';
import 'shared/yomitan_glossary_fixtures.dart';

/// A 1x1 red PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
);

void main() {
  late AppDatabase db;
  late DictionaryRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = DictionaryRepository(db);
    // Each test's database starts its ids at 1 again, and images are cached
    // by dictionary id and path.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  tearDown(() => db.close());

  /// Renders one glossary item, or a whole row when [glossary] is a list,
  /// stored as an import stores it: objects as themselves ([legacy]: as
  /// JSON strings, like rows imported before 1.47).
  Future<List<String>> pump(
    WidgetTester tester,
    Object glossary, {
    int dictionaryId = 1,
    bool legacy = false,
  }) async {
    final items = [
      for (final item in glossary is List ? glossary : [glossary])
        !legacy && item is String ? stored(item) : item,
    ];
    final taps = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dictionaryRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StructuredGlossaryView(
                glossaries: jsonEncode(items),
                dictionaryId: dictionaryId,
                style: const TextStyle(fontSize: 16),
                onWordTap: taps.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return taps;
  }

  Finder text(String s) => find.textContaining(s, findRichText: true);

  testWidgets('a Jitendex entry shows badges, senses, furigana and examples', (
    tester,
  ) async {
    await pump(tester, jitendexTaberu);

    expect(find.text('1-dan'), findsOneWidget);
    expect(find.text('transitive'), findsOneWidget);
    expect(find.text('①'), findsOneWidget);
    expect(find.text('②'), findsOneWidget);
    expect(text('to eat'), findsWidgets);
    expect(text('to live on (e.g. a salary); to live off'), findsOneWidget);
    // Furigana over the example sentence's kanji.
    expect(find.text('くだ'), findsOneWidget);
    expect(text('You should eat more fruit.'), findsOneWidget);
    expect(text('structured-content'), findsNothing);
    expect(text('"tag"'), findsNothing);
  });

  testWidgets('a definition imported before 1.47 still shows', (tester) async {
    await pump(tester, jitendexTaberu, legacy: true);

    expect(find.text('1-dan'), findsOneWidget);
    expect(find.text('②'), findsOneWidget);
    expect(text('to live on (e.g. a salary); to live off'), findsOneWidget);
    expect(text('"tag"'), findsNothing);
  });

  testWidgets('tapping a Japanese word in an example looks it up', (
    tester,
  ) async {
    final taps = await pump(tester, jitendexGakkou);

    await tester.tap(text('はたくさんの'));

    // Without MeCab (unit tests) a whole Japanese run is one target; the
    // ruby base text is part of it.
    expect(taps.single, startsWith('この学校'));
  });

  testWidgets('tapping a link looks up its query', (tester) async {
    final taps = await pump(tester, jitendexRedirect);

    await tester.tap(find.text('働'));

    expect(taps, ['労働相']);
  });

  testWidgets('a JMdict link with a raw Japanese query looks it up', (
    tester,
  ) async {
    final taps = await pump(tester, jmdictNotes);

    final paragraph = tester.renderObject<RenderParagraph>(text('see: '));
    final caret = paragraph.getOffsetForCaret(
      const TextPosition(offset: 'see: '.length),
      Rect.zero,
    );
    await tester.tapAt(paragraph.localToGlobal(caret + const Offset(4, 8)));

    expect(taps, ['丸']);
  });

  testWidgets('attributes of the wrong type do not break the definition', (
    tester,
  ) async {
    // Hand-imported dictionaries are not checked against Yomitan's schema.
    await pump(
      tester,
      jsonEncode({
        'type': 'structured-content',
        'content': [
          {'tag': 'a', 'href': 3, 'title': 7, 'content': 'to drink'},
          {
            'tag': 'img',
            'path': 'x.png',
            'width': '12',
            'height': true,
            'alt': 5,
            'title': ['t'],
          },
        ],
      }),
    );

    expect(text('to drink'), findsOneWidget);
    expect(text('structured-content'), findsNothing);
  });

  testWidgets('plain glosses beside structured content stay apart', (
    tester,
  ) async {
    await pump(tester, ['to eat', 'to consume', jmdictNotes]);

    expect(find.text('to eat', findRichText: true), findsOneWidget);
    expect(find.text('to consume', findRichText: true), findsOneWidget);
  });

  testWidgets('a parent rebuild keeps the definition and the newest callback', (
    tester,
  ) async {
    final taps = <String>[];
    var generation = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dictionaryRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                final g = generation;
                return StructuredGlossaryView(
                  glossaries: jsonEncode([jitendexRedirect]),
                  dictionaryId: 1,
                  style: const TextStyle(fontSize: 16),
                  onWordTap: (word) => taps.add('$g:$word'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = find.byType(HitTestableRichText).first;
    final before = tester.widget(paragraph);

    rebuild(() => generation++);
    await tester.pump();

    expect(identical(tester.widget(paragraph), before), isTrue);
    await tester.tap(find.text('働'));
    expect(taps, ['1:労働相']);
  });

  testWidgets('an opened section stays open when its row scrolls away and '
      'back', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dictionaryRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                StructuredGlossaryView(
                  glossaries: jsonEncode([wtyEnglishTaberu]),
                  dictionaryId: 1,
                  style: const TextStyle(fontSize: 16),
                ),
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 200, child: Text('filler $i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grammar'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 4000));
    await tester.pumpAndSettle();

    expect(text('transitive ichidan'), findsOneWidget);
  });

  testWidgets('Wiktionary sections start collapsed and open on tap', (
    tester,
  ) async {
    await pump(tester, wtyEnglishTaberu);
    expect(find.text('Grammar'), findsOneWidget);
    expect(text('transitive ichidan'), findsNothing);

    await tester.tap(find.text('Grammar'));
    await tester.pumpAndSettle();

    expect(text('transitive ichidan'), findsOneWidget);
    expect(text('to make a living'), findsOneWidget);
  });

  testWidgets('a section titled in Japanese opens on tap, not a lookup', (
    tester,
  ) async {
    // Japanese Wiktionary names its sections in Japanese.
    final taps = await pump(
      tester,
      jsonEncode({
        'type': 'structured-content',
        'content': {
          'tag': 'details',
          'content': [
            {'tag': 'summary', 'content': '語源'},
            {'tag': 'div', 'content': 'from Old Japanese'},
          ],
        },
      }),
    );
    expect(text('from Old Japanese'), findsNothing);

    await tester.tap(text('語源'));
    await tester.pumpAndSettle();

    expect(text('from Old Japanese'), findsOneWidget);
    expect(taps, isEmpty);
  });

  testWidgets('JMdict keeps its compact gloss line and its note markers', (
    tester,
  ) async {
    await pump(tester, jmdictSourceLanguages);

    expect(text('bitch; witch; ugly woman; dog'), findsOneWidget);
    expect(find.text('🌐'), findsOneWidget);
    expect(text('espada'), findsOneWidget);
  });

  testWidgets('forms tables render as tables', (tester) async {
    await pump(tester, jmdictFormsTable);

    expect(find.byType(Table), findsOneWidget);
    expect(text('おなじく'), findsOneWidget);
  });

  group('images', () {
    const path = 'jitendex/graphics/bb516c272145714035ab4a8ce53787cd.avif';

    testWidgets(
      'a stored image is drawn, and tapping it opens it full screen',
      (tester) async {
        final id = await tester.runAsync(() async {
          final id = await repo.insertDictionary('Jitendex.org [2026-10-03]');
          await repo.insertMedia(id, [(path, _png)]);
          return id;
        });
        await pump(tester, jitendexGraphic, dictionaryId: id!);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(find.byType(Image), findsOneWidget);
        expect(text('Stan Shebs (CC BY-SA 3.0)'), findsOneWidget);

        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsNothing);
      },
    );

    testWidgets('the full-screen image outlives the definition behind it', (
      tester,
    ) async {
      final id = await tester.runAsync(() async {
        final id = await repo.insertDictionary('Jitendex.org [2026-10-03]');
        await repo.insertMedia(id, [(path, _png)]);
        return id;
      });
      await pump(tester, jitendexGraphic, dictionaryId: id!);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      // The results behind the viewer change (an import finished), so the
      // definition goes while the viewer stays and is built again.
      Widget app() => ProviderScope(
        overrides: [dictionaryRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pumpWidget(app());
      await tester.pumpWidget(app());

      expect(tester.takeException(), isNull);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('an image shown again is read and decoded once', (
      tester,
    ) async {
      final reads = _CountingRepository(db);
      final id = await tester.runAsync(() async {
        final id = await reads.insertDictionary('Jitendex.org [2026-10-03]');
        await reads.insertMedia(id, [(path, _png)]);
        return id;
      });
      Future<void> show() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [dictionaryRepositoryProvider.overrideWithValue(reads)],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: StructuredGlossaryView(
                    glossaries: jsonEncode([jitendexGraphic]),
                    dictionaryId: id!,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      await show();
      // The definition leaves the screen, then comes back.
      await tester.pumpWidget(const SizedBox());
      await show();

      expect(reads.mediaReads, 1);
    });

    testWidgets('a missing image takes no space', (tester) async {
      await pump(tester, jitendexGraphic);
      // The image cache loads outside the test's fake clock.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(tester.getSize(find.byType(Image)), Size.zero);
      expect(text('Japanese andromeda'), findsOneWidget);
    });

    testWidgets('a word next to an inline image is still tappable', (
      tester,
    ) async {
      final item = jsonEncode({
        'type': 'structured-content',
        'content': [
          '見る',
          {
            'tag': 'img',
            'path': 'glyph.png',
            'width': 1,
            'height': 1,
            'sizeUnits': 'em',
          },
          'もの',
        ],
      });
      final taps = await pump(tester, item);

      final paragraph = find.byType(RichText).first;
      await tester.tapAt(tester.getTopLeft(paragraph) + const Offset(4, 8));

      expect(taps, ['見る']);
    });
  });
}

class _CountingRepository extends DictionaryRepository {
  _CountingRepository(super.db);

  int mediaReads = 0;

  @override
  Future<Uint8List?> getMedia(int dictionaryId, String path) {
    mediaReads++;
    return super.getMedia(dictionaryId, path);
  }
}
