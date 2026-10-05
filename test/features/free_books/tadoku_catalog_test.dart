import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/free_books/data/services/tadoku_catalog.dart';

const _catalog = '''{"books": [
  {"i": 1, "t": "ちょっと来て！", "l": -1, "cv": "https://tadoku.org/c1.jpg",
   "pdf": "https://tadoku.org/b1.pdf", "au": false, "pg": 17,
   "ch": 0, "r": "ちょっときて！", "tx": true},
  {"i": 2, "t": "日下川の猿猴", "l": 1, "cv": "https://tadoku.org/c2.jpg",
   "pdf": "https://tadoku.org/b2.pdf", "au": true, "pg": 14,
   "ch": 1200, "r": "くさかがわのえんこう", "tx": false},
  {"i": 3, "t": "美知子の星空", "l": 5, "cv": "https://tadoku.org/c3.jpg",
   "pdf": "https://tadoku.org/b3.pdf", "au": false, "pg": 50,
   "ch": 0, "r": "みちこのほしぞら", "tx": true}
]}''';

void main() {
  final books = parseTadokuCatalog(_catalog);

  List<int> ids(TadokuQuery query, {Set<int> inLibrary = const {}}) => [
    for (final book in filterTadokuBooks(
      books,
      query,
      isInLibrary: (book) => inLibrary.contains(book.id),
    ))
      book.id,
  ];

  test('parses the bundled catalog format', () {
    final book = books[1];
    expect(book.title, '日下川の猿猴');
    expect(book.titleReading, 'くさかがわのえんこう');
    expect(book.level, 1);
    expect(book.pdfUrl, Uri.parse('https://tadoku.org/b2.pdf'));
    expect(book.coverUrl, Uri.parse('https://tadoku.org/c2.jpg'));
    expect(book.pageCount, 14);
    expect(book.charCount, 1200);
    expect(book.hasAudio, isTrue);
    expect(book.hasText, isFalse);
    expect(book.pageUrl, Uri.parse('https://tadoku.org/japanese/book/2/'));
    expect(books.first.level, -1, reason: 'Start');
  });

  test('filters by level, keeping catalog order', () {
    expect(ids(const TadokuQuery()), [1, 2, 3]);
    expect(ids(const TadokuQuery(levels: {5, -1})), [1, 3]);
  });

  test('searches titles and readings, in kana or romaji', () {
    expect(ids(const TadokuQuery(text: '星空')), [3]);
    expect(ids(const TadokuQuery(text: 'えんこう')), [2]);
    expect(ids(const TadokuQuery(text: 'エンコウ')), [2]);
    expect(ids(const TadokuQuery(text: 'kusaka')), [2]);
  });

  test('hides books already in the library', () {
    expect(ids(const TadokuQuery(hideInLibrary: true), inLibrary: {1}), [2, 3]);
    expect(ids(const TadokuQuery(), inLibrary: {1}), [1, 2, 3]);
  });
}
