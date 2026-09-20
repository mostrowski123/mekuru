// Not a test of behaviour: a scripted tour that puts the app into the states
// the App Store screenshots show. At each stop it prints `@@SHOT <name>` and
// holds still for a few seconds; tools/app_store_screenshots.sh watches the
// log and captures the simulator's screen. All content is public domain
// (Natsume Soseki, Dazai Osamu, Miyazawa Kenji) or written here.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:mekuru/features/reader/presentation/widgets/lookup_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

const _books = [
  ('吾輩は猫である', '夏目漱石', Color(0xFFB23A48)),
  ('走れメロス', '太宰治', Color(0xFF2F6690)),
  ('銀河鉄道の夜', '宮沢賢治', Color(0xFF1B263B)),
  ('こころ', '夏目漱石', Color(0xFF6B705C)),
];

// The opening of 吾輩は猫である (public domain).
const _text = [
  '吾輩は猫である。名前はまだ無い。',
  'どこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。'
      '吾輩はここで始めて人間というものを見た。しかもあとで聞くとそれは書生という人間中で一番獰悪な種族であったそうだ。'
      'この書生というのは時々我々を捕えて煮て食うという話である。しかしその当時は何という考もなかったから別段恐しいとも思わなかった。'
      'ただ彼の掌に載せられてスーと持ち上げられた時何だかフワフワした感じがあったばかりである。'
      '掌の上で少し落ちついて書生の顔を見たのがいわゆる人間というものの見始であろう。',
  'この時妙なものだと思った感じが今でも残っている。第一毛をもって装飾されべきはずの顔がつるつるしてまるで薬缶だ。'
      'その後猫にもだいぶ逢ったがこんな片輪には一度も出会わした事がない。のみならず顔の真中があまりに突起している。'
      'そうしてその穴の中から時々ぷうぷうと煙を吹く。どうも咽せぽくて実に弱った。'
      'これが人間の飲む煙草というものである事はようやくこの頃知った。',
];

const _words = [
  ('吾輩', 'わがはい', ['I; me (used by men of high standing, archaic)']),
  ('猫', 'ねこ', ['cat']),
  ('名前', 'なまえ', ['name', 'given name']),
  ('見当', 'けんとう', ['estimate; guess', 'aim; direction']),
  ('薄暗い', 'うすぐらい', ['dim; gloomy']),
  ('泣く', 'なく', ['to cry; to weep']),
  ('記憶', 'きおく', ['memory; recollection']),
  ('人間', 'にんげん', ['human being; person']),
  ('書生', 'しょせい', ['student', 'houseboy who studies while working']),
  ('種族', 'しゅぞく', ['race; tribe; species']),
  ('話', 'はなし', ['talk; story']),
  ('当時', 'とうじ', ['at that time; in those days']),
  ('掌', 'てのひら', ['palm (of the hand)']),
  ('感じ', 'かんじ', ['feeling; impression']),
  ('顔', 'かお', ['face']),
  ('思う', 'おもう', ['to think; to feel']),
  ('見る', 'みる', ['to see; to look at']),
  ('聞く', 'きく', ['to hear; to ask']),
  ('食う', 'くう', ['to eat (rough)']),
  ('煙草', 'たばこ', ['tobacco; cigarette']),
  ('煙', 'けむり', ['smoke']),
  ('穴', 'あな', ['hole']),
  ('真中', 'まんなか', ['middle; centre']),
  ('事', 'こと', ['thing; matter']),
];

Future<List<int>> _cover(String title, String author, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(600, 900);
  canvas.drawRect(Offset.zero & size, Paint()..color = color);
  canvas.drawRect(
    const Rect.fromLTWH(30, 30, 540, 840),
    Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  void vertical(String text, double x, double top, double fontSize) {
    var y = top;
    for (final rune in text.runes) {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(rune),
          style: TextStyle(color: Colors.white, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x - painter.width / 2, y));
      y += fontSize * 1.15;
    }
  }

  vertical(title, 380, 110, 72);
  vertical(author, 200, 420, 40);
  final image = await recorder.endRecording().toImage(600, 900);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

Future<String> _epub(
  Directory dir,
  int index,
  String title,
  String author,
  List<int> cover,
) async {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
  add(
    'META-INF/container.xml',
    utf8.encode(
      '<?xml version="1.0"?><container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
      '<rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
  );
  add(
    'OEBPS/content.opf',
    utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>$title</dc:title><dc:creator>$author</dc:creator>'
      '<dc:language>ja</dc:language>'
      '<meta name="primary-writing-mode" content="vertical-rl"/>'
      '<meta name="cover" content="cover"/></metadata><manifest>'
      '<item id="cover" href="cover.png" media-type="image/png" '
      'properties="cover-image"/>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine page-progression-direction="rtl">'
      '<itemref idref="c1"/></spine></package>',
    ),
  );
  add('OEBPS/cover.png', cover);
  final body = [
    for (var i = 0; i < 6; i++)
      for (final paragraph in _text) '<p>$paragraph</p>',
  ].join();
  add(
    'OEBPS/c1.xhtml',
    utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>一</title>'
      '<style>html, body { writing-mode: vertical-rl; }</style></head>'
      '<body>$body</body></html>',
    ),
  );
  final path = p.join(dir.path, 'book_$index.epub');
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
  return path;
}

void main() {
  // The word is tapped with a real touch on the simulator; by default the
  // test binding swallows device touches while a test runs.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .shouldPropagateDevicePointerEvents =
      true;

  testWidgets('App Store screenshot tour', (tester) async {
    // The test harness builds its own MaterialApp, which would show the
    // debug banner in every screenshot.
    WidgetsApp.debugAllowBannerOverride = false;
    Future<void> shot(String name) async {
      // ignore: avoid_print
      print('@@SHOT $name');
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    final db = createTestDatabase();
    addTearDown(db.close);
    await db
        .into(db.dictionaryMetas)
        .insert(
          DictionaryMetasCompanion.insert(
            name: 'Japanese–English',
            sortOrder: const Value(0),
          ),
        );
    for (final (expression, reading, glossaries) in _words) {
      await db
          .into(db.dictionaryEntries)
          .insert(
            DictionaryEntriesCompanion.insert(
              expression: expression,
              reading: Value(reading),
              glossaries: jsonEncode(glossaries),
              dictionaryId: 1,
            ),
          );
    }
    await MecabService.instance.init();

    final temp = await Directory(
      p.join((await getTemporaryDirectory()).path, 'shots'),
    ).create(recursive: true);
    // Only what this run imports is removed afterwards: the simulator may
    // hold a library from manual testing.
    final booksDir = await appBooksDir();
    final before = booksDir.existsSync()
        ? booksDir.listSync().map((e) => e.path).toSet()
        : <String>{};
    addTearDown(() async {
      await temp.delete(recursive: true);
      if (!booksDir.existsSync()) return;
      for (final entry in booksDir.listSync()) {
        if (!before.contains(entry.path)) await entry.delete(recursive: true);
      }
    });
    // Imported last to first so the book that gets opened sits first.
    for (final (i, (title, author, color))
        in _books.indexed.toList().reversed) {
      final cover = await tester.runAsync(() => _cover(title, author, color));
      final path = await _epub(temp, i, title, author, cover!);
      await BookRepository(db).importEpub(path);
    }

    final readerSettings = InMemoryReaderSettingsStorage();
    await readerSettings.save(
      const ReaderSettings(furiganaMode: FuriganaMode.hide),
    );
    await tester.pumpWidget(
      buildIntegrationTestApp(
        db: db,
        home: const LibraryScreen(),
        readerSettingsStorage: readerSettings,
      ),
    );
    await pumpUntilVisible(tester, find.text(_books.first.$1));
    await shot('01-library');

    await tester.tap(find.text(_books.first.$1).first);
    await pumpUntilVisible(tester, find.byType(CustomEpubViewer));
    await pumpUntilGone(
      tester,
      find.byKey(const Key('reader-loading-overlay')),
    );
    await tester.pump(const Duration(seconds: 3));
    await shot('02-reader');

    // A synthetic tester tap does not reach the WKWebView on iOS, so the word
    // is tapped from outside (a real touch on the simulator) while this waits.
    // ignore: avoid_print
    print('@@WAITTAP');
    var found = false;
    for (var tick = 0; tick < 160 && !found; tick++) {
      await tester.pump(const Duration(milliseconds: 250));
      found = find.byType(LookupSheet).evaluate().isNotEmpty;
    }
    if (!found) {
      // The library and reader shots are still good; say so and stop.
      // ignore: avoid_print
      print('@@NOTE no lookup sheet appeared, skipping 03-lookup');
      return;
    }
    await tester.pump(const Duration(seconds: 2));
    await shot('03-lookup');
  });
}
