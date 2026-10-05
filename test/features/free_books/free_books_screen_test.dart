import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/models/tadoku_book.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/free_books/presentation/screens/free_books_screen.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';

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

TadokuBook _reader(int id, String title, int level, {bool hasText = true}) =>
    TadokuBook(
      id: id,
      title: title,
      titleReading: '',
      level: level,
      coverUrl: Uri.parse('https://tadoku.org/c$id.jpg'),
      pdfUrl: Uri.parse('https://tadoku.org/b$id.pdf'),
      pageCount: 12,
      charCount: 0,
      hasAudio: true,
      hasText: hasText,
    );

final _readers = [
  _reader(11, 'ちょっと来て！', -1),
  _reader(12, 'たのしいえんそく', 0, hasText: false),
  _reader(13, '日下川の猿猴', 2),
];

class _RecordingDownloads extends FreeBookDownloadNotifier {
  final requested = <int>[];

  @override
  Future<void> downloadAozora(AozoraWork work) async => requested.add(work.id);

  @override
  Future<void> downloadTadoku(TadokuBook book) async => requested.add(book.id);
}

/// A library book; [source] is set when it was downloaded from Free books.
Book _book(String title, {String type = 'epub', String? source, int id = 7}) =>
    Book(
      id: id,
      title: title,
      filePath: '/books/$id',
      bookType: type,
      totalPages: 0,
      readProgress: 0,
      dateAdded: DateTime(2026),
      sourceId: source,
    );

/// Pumps the Free books screen; Aozora tests open its second tab.
Future<_RecordingDownloads> _pump(
  WidgetTester tester, {
  List<AozoraWork>? works,
  List<Book> books = const [],
  bool aozora = true,
}) async {
  final downloads = _RecordingDownloads();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aozoraCatalogProvider.overrideWith((ref) async => works ?? _works),
        tadokuCatalogProvider.overrideWith((ref) async => _readers),
        booksProvider.overrideWith((ref) => Stream.value(books)),
        freeBookDownloadProvider.overrideWith(() => downloads),
      ],
      child: buildLocalizedTestApp(home: const FreeBooksScreen()),
    ),
  );
  await tester.pumpAndSettle();
  if (aozora) {
    await tester.tap(find.text('Aozora Bunko'));
    await tester.pumpAndSettle();
  }
  return downloads;
}

void main() {
  testWidgets('opens on graded readers, with levels and Pages only', (
    tester,
  ) async {
    await _pump(tester, aozora: false);

    expect(find.text('ちょっと来て！'), findsOneWidget);
    expect(find.text('日下川の猿猴'), findsOneWidget);
    // Badges: Start, L0, and tadoku.org's own JLPT level for L2.
    expect(find.text('Start'), findsNWidgets(2)); // chip and badge
    expect(find.text('L2 · N4'), findsNWidgets(2));
    expect(find.text('Pages only'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'L2 · N4'));
    await tester.pumpAndSettle();

    expect(find.text('日下川の猿猴'), findsOneWidget);
    expect(find.text('ちょっと来て！'), findsNothing);
  });

  testWidgets('a graded reader\'s sheet credits it and downloads it', (
    tester,
  ) async {
    final downloads = await _pump(tester, aozora: false);

    await tester.ensureVisible(find.text('たのしいえんそく'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('たのしいえんそく'));
    await tester.pumpAndSettle();

    expect(find.textContaining("words can't be tapped"), findsOneWidget);
    expect(find.textContaining('CC BY-NC-ND 4.0'), findsWidgets);
    expect(find.text('12 pages'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(downloads.requested, [12]);
  });

  testWidgets('a graded reader in the library offers Read', (tester) async {
    await _pump(
      tester,
      aozora: false,
      books: [_book('日下川の猿猴', type: 'manga', source: 'tadoku:13')],
    );

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.ensureVisible(find.text('日下川の猿猴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日下川の猿猴'));
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

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

    expect(find.textContaining('not official JLPT ratings'), findsOneWidget);
    expect(find.textContaining('typical learner'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(downloads.requested, [1]);
  });

  testWidgets('a book already in the library offers Read instead', (
    tester,
  ) async {
    await _pump(tester, books: [_book('手袋を買いに', source: 'aozora:1')]);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(find.text('手袋を買いに'));
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('only the downloaded work counts, not one with its title', (
    tester,
  ) async {
    // Two works share a title. The library holds the second one, plus a
    // book of the same title the user imported, which is neither.
    await _pump(
      tester,
      works: [
        _work(1, '夢', author: '夏目 漱石', level: 4),
        _work(2, '夢', author: '芥川 竜之介', level: 4),
      ],
      books: [
        _book('夢', source: 'aozora:2'),
        _book('夢', id: 8),
      ],
    );

    Finder checkOn(String author) => find.descendant(
      of: find.ancestor(
        of: find.textContaining(author),
        matching: find.byType(ListTile),
      ),
      matching: find.byIcon(Icons.check_circle),
    );
    expect(checkOn('芥川'), findsOneWidget);
    expect(checkOn('夏目'), findsNothing);

    await tester.tap(find.textContaining('夏目'));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Read'), findsNothing);
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
