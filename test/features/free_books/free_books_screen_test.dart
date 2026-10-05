import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/free_books/presentation/screens/free_books_screen.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/stats/presentation/providers/stats_providers.dart';

import '../../test_app.dart';

AozoraWork _work(
  int id,
  String title, {
  String reading = '',
  String author = '',
  String authorReading = '',
  int level = 3,
  AozoraSpelling spelling = AozoraSpelling.modern,
  int chars = 5000,
  int popularity = 0,
}) => AozoraWork(
  id: id,
  title: title,
  titleReading: reading,
  author: author,
  authorReading: authorReading,
  xhtmlPath: '000001/files/${id}_1.html',
  genre: AozoraGenre.fiction,
  spelling: spelling,
  charCount: chars,
  jlptEstimate: level,
  popularity: popularity,
);

final _works = [
  _work(
    1,
    '手袋を買いに',
    reading: 'てぶくろをかいに',
    author: '新美 南吉',
    authorReading: 'にいみ なんきち',
    level: 4,
    popularity: 300,
  ),
  _work(
    2,
    '走れメロス',
    reading: 'はしれメロス',
    author: '太宰 治',
    authorReading: 'だざい おさむ',
    level: 1,
    popularity: 900,
  ),
  _work(
    3,
    '舞姫',
    reading: 'まいひめ',
    author: '森 鴎外',
    authorReading: 'もり おうがい',
    level: 3,
    spelling: AozoraSpelling.oldKanji,
    popularity: 500,
  ),
];

class _RecordingDownloads extends FreeBookDownloadNotifier {
  final requested = <int>[];

  @override
  Future<void> downloadAozora(AozoraWork work) async => requested.add(work.id);
}

Book _book(String title) => Book(
  id: 7,
  title: title,
  filePath: '/books/7',
  bookType: 'epub',
  totalPages: 0,
  readProgress: 0,
  dateAdded: DateTime(2026),
);

Future<_RecordingDownloads> _pump(
  WidgetTester tester, {
  List<Book> books = const [],
}) async {
  final downloads = _RecordingDownloads();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aozoraCatalogProvider.overrideWith((ref) async => _works),
        sessionsProvider.overrideWith((ref) => Stream.value(const [])),
        booksProvider.overrideWith((ref) => Stream.value(books)),
        freeBookDownloadProvider.overrideWith(() => downloads),
      ],
      child: buildLocalizedTestApp(home: const FreeBooksScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return downloads;
}

void main() {
  testWidgets('opens on easy picks: easy levels in modern spelling', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('手袋を買いに'), findsOneWidget);
    // ~N1, and pre-war spelling, are outside easy picks.
    expect(find.text('走れメロス'), findsNothing);
    expect(find.text('舞姫'), findsNothing);
    expect(find.text('1 book'), findsOneWidget);
    expect(find.textContaining('~N4'), findsOneWidget);
  });

  testWidgets('clearing filters shows everything, most popular first', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(find.text('3 books'), findsOneWidget);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['走れメロス', '舞姫', '手袋を買いに']);

    // And the button flips back to re-apply the preset.
    await tester.tap(find.text('Easy picks'));
    await tester.pumpAndSettle();
    expect(find.text('1 book'), findsOneWidget);
  });

  testWidgets('searches in romaji after the debounce', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dazai');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('走れメロス'), findsOneWidget);
    expect(find.text('手袋を買いに'), findsNothing);
  });

  testWidgets('the details sheet explains the estimate and downloads', (
    tester,
  ) async {
    final downloads = await _pump(tester);

    await tester.tap(find.text('手袋を買いに'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not official JLPT ratings'),
      findsOneWidget,
    );
    expect(find.textContaining('typical learner'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(downloads.requested, [1]);
  });

  testWidgets('a book already in the library offers Read instead', (
    tester,
  ) async {
    await _pump(tester, books: [_book('手袋を買いに')]);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(find.text('手袋を買いに'));
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('the level sheet changes the filter live', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Level'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '~N1'));
    await tester.pumpAndSettle();
    // Close the sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('走れメロス'), findsOneWidget);
    expect(find.text('2 books'), findsOneWidget);
  });
}
