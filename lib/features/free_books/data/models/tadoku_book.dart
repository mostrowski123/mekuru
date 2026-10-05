import 'package:mekuru/features/free_books/data/catalog_search.dart';

/// The publisher's name as credited under the books' licence.
const tadokuPublisher = 'NPO多言語多読';

/// A free graded reader by NPO Tadoku Supporters, under CC BY-NC-ND 4.0.
/// Its PDF is downloaded straight from tadoku.org when the user asks, never
/// hosted or changed by Mekuru.
class TadokuBook {
  TadokuBook({
    required this.id,
    required this.title,
    required this.titleReading,
    required this.level,
    required this.coverUrl,
    required this.pdfUrl,
    required this.pageCount,
    required this.charCount,
    required this.hasAudio,
    required this.hasText,
  }) : searchText = searchFields([title, titleReading]);

  /// One entry of `assets/free_books/tadoku.json`, written by
  /// tools/build_tadoku_catalog.py.
  factory TadokuBook.fromJson(Map<String, dynamic> json) => TadokuBook(
    id: json['i'] as int,
    title: json['t'] as String,
    titleReading: json['r'] as String,
    level: json['l'] as int,
    coverUrl: Uri.parse(json['cv'] as String),
    pdfUrl: Uri.parse(json['pdf'] as String),
    pageCount: json['pg'] as int,
    charCount: json['ch'] as int,
    hasAudio: json['au'] as bool,
    hasText: json['tx'] as bool,
  );

  final int id;
  final String title;
  final String titleReading;

  /// Tadoku level: -1 for Start, then 0 (easiest) to 5.
  final int level;
  final Uri coverUrl;
  final Uri pdfUrl;
  final int pageCount;

  /// 0 when tadoku.org doesn't say.
  final int charCount;

  /// Whether tadoku.org has its audio, played there.
  final bool hasAudio;

  /// Whether its PDF has Japanese text to tap. Without it ("pages only"),
  /// words need OCR.
  final bool hasText;

  /// Title and reading, folded for search.
  final String searchText;

  /// The book's page on tadoku.org (credits, audio).
  Uri get pageUrl => Uri.parse('https://tadoku.org/japanese/book/$id/');
}
