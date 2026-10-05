// Free books end to end: pick a work on the Aozora tab, download it from a
// local stand-in for aozora.gr.jp, and open the converted EPUB in the reader.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/free_books/presentation/screens/free_books_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

const _title = '手袋を買いに';
const _xhtmlPath = '000001/files/1_1.html';
const _gaiji = '../../../gaiji/1-84/1-84-77.png';

final _work = AozoraWork(
  id: 1,
  title: _title,
  titleReading: 'てぶくろをかいに',
  author: '新美 南吉',
  authorReading: 'にいみ なんきち',
  xhtmlPath: _xhtmlPath,
  genre: AozoraGenre.children,
  spelling: AozoraSpelling.modern,
  charCount: 5000,
  jlptEstimate: 4,
  popularity: 1,
);

/// An Aozora-shaped page: metadata, a heading in an indent div, long lines
/// with rb/rp ruby, a gaiji image and the bibliographic block. Served as
/// UTF-8 (the converter honours the declaration); Shift_JIS decoding has its
/// own unit tests.
String _page() {
  final line =
      '　<ruby><rb>寒</rb><rp>（</rp><rt>さむ</rt><rp>）</rp></ruby>い冬が'
          '北方から、狐の親子の棲んでいる森へもやって来ました。' *
      6;
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja"><head>'
      '<title>$_title</title></head><body>'
      '<div class="metadata"><h1 class="title">$_title</h1>'
      '<h2 class="author">新美南吉</h2></div>'
      '<div class="main_text"><br />'
      '<div class="jisage_3" style="margin-left: 3em">'
      '<h4 class="naka-midashi">一</h4></div><br />'
      '${'$line<br />\n' * 12}'
      '<img src="$_gaiji" alt="※(「てへん＋劣」)" class="gaiji" /><br />'
      '</div>'
      '<div class="bibliographical_information"><hr />'
      '底本：「新美南吉童話集」<br />入力：テスト<br /></div>'
      '</body></html>';
}

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  final requested = <String>[];
  late Set<String> booksBefore;

  setUp(() async {
    requested.clear();
    final dir = await appBooksDir();
    booksBefore = await dir.exists()
        ? dir.listSync().map((e) => e.path).toSet()
        : <String>{};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requested.add(request.uri.path);
      final response = request.response;
      switch (request.uri.path) {
        case '/cards/$_xhtmlPath':
          response.add(utf8.encode(_page()));
        case '/gaiji/1-84/1-84-77.png':
          response.add(_png);
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    // Only remove what this test imported: it may run on a real device.
    final dir = await appBooksDir();
    if (!await dir.exists()) return;
    for (final entity in dir.listSync()) {
      if (!booksBefore.contains(entity.path)) {
        entity.deleteSync(recursive: true);
      }
    }
  });

  testWidgets('downloads an Aozora book into the library and opens it', (
    tester,
  ) async {
    final l10n = await loadExpectedL10n();
    final db = createTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const FreeBooksScreen(),
        extraOverrides: [
          aozoraBaseUrlProvider.overrideWithValue(
            'http://127.0.0.1:${server.port}/cards/',
          ),
          aozoraCatalogProvider.overrideWith((ref) async => [_work]),
        ],
      ),
    );

    // Easy picks shows the ~N4 children's story.
    await pumpUntilVisible(tester, find.text(_title));
    await tester.tap(find.text(_title));
    await pumpUntilVisible(tester, find.text(l10n.commonDownload));
    await tester.tap(find.text(l10n.commonDownload));

    // Once the library has the book, the sheet offers Read instead.
    await pumpUntilVisible(
      tester,
      find.text(l10n.freeBooksRead),
      timeout: const Duration(seconds: 30),
    );
    expect(requested, ['/cards/$_xhtmlPath', '/gaiji/1-84/1-84-77.png']);
    final book = (await db.select(db.books).get()).single;
    expect(book.title, _title);
    expect(book.bookType, 'epub');
    expect(book.primaryWritingMode, 'vertical-rl');
    expect(book.hasVerticalCss, isTrue);

    await tester.tap(find.text(l10n.freeBooksRead));
    await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
    await pumpUntilGone(
      tester,
      find.byKey(const Key('reader-loading-overlay')),
    );
  });
}
