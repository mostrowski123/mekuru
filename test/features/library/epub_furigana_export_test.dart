import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/utils/japanese_text.dart';
import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/furigana_generator.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:xml/xml.dart';

class _FakeTokenizer implements FuriganaTokenizer {
  _FakeTokenizer(this._byInput, {this.ready = true});
  final Map<String, List<TokenInfo>> _byInput;
  final bool ready;

  @override
  Future<bool> ensureReady() async => ready;

  @override
  List<TokenInfo> tokenize(String text) =>
      _byInput[text] ?? const <TokenInfo>[];
}

TokenInfo _tok(String surface, String reading, int start) => TokenInfo(
  surface: surface,
  dictionaryForm: surface,
  reading: reading,
  pos: '',
  startInText: start,
);

const _containerXml =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

const _contentOpf =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="id"><metadata/>'
    '<manifest>'
    '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="css" href="style.css" media-type="text/css"/>'
    '<item id="img" href="image.png" media-type="image/png"/>'
    '</manifest>'
    '<spine><itemref idref="c1"/></spine></package>';

final _imageBytes = Uint8List.fromList(List.generate(64, (i) => i * 3 % 251));

Uint8List buildTestEpub(String chapterXhtml, {bool withMimetype = true}) {
  final archive = Archive();
  if (withMimetype) {
    archive.addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    );
  }
  archive.addFile(
    ArchiveFile.bytes('META-INF/container.xml', utf8.encode(_containerXml)),
  );
  archive.addFile(
    ArchiveFile.bytes('OEBPS/content.opf', utf8.encode(_contentOpf)),
  );
  archive.addFile(
    ArchiveFile.bytes('OEBPS/chapter1.xhtml', utf8.encode(chapterXhtml)),
  );
  archive.addFile(ArchiveFile.bytes('OEBPS/style.css', utf8.encode('body{}')));
  archive.addFile(ArchiveFile.bytes('OEBPS/image.png', _imageBytes));
  return ZipEncoder().encodeBytes(archive);
}

String chapter(String body) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!DOCTYPE html>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>漢字の本</title>'
    '<style>p { color: red; }</style></head>'
    '<body>$body</body></html>';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('epub_export_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeEpub(Uint8List bytes) async {
    final file = File('${tempDir.path}/book.epub');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('exportFileName', () {
    test('sanitizes hostile characters and appends the suffix', () {
      expect(exportFileName('吾輩は猫である'), '吾輩は猫である (furigana).epub');
      expect(exportFileName('a/b:c?'), 'a_b_c_ (furigana).epub');
      expect(exportFileName(''), 'book (furigana).epub');
      expect(exportFileName('あ' * 200).length, lessThan(100));
    });
  });

  group('furiganaTargets', () {
    test('skips ruby/script/style/head subtrees and kana-only nodes', () {
      final doc = XmlDocument.parse(
        chapter(
          '<p>今日</p>'
          '<p><ruby>既存<rt>きそん</rt></ruby></p>'
          '<p>かなだけ</p>'
          '<script>var x = "漢字";</script>',
        ),
        entityMapping: const XmlDefaultEntityMapping.html5(),
      );
      final targets = furiganaTargets(doc);
      expect(targets.map((t) => t.value).toList(), ['今日']);
    });
  });

  group('spliceRuby', () {
    test('wraps f-carrying segments in ruby and keeps plain text', () {
      final doc = XmlDocument.parse('<p>a今日b</p>');
      final node = doc.descendants.whereType<XmlText>().single;
      spliceRuby(node, [
        {'t': 'a'},
        {'t': '今日', 'f': 'きょう'},
        {'t': 'b'},
      ]);
      expect(doc.toXmlString(), '<p>a<ruby>今日<rt>きょう</rt></ruby>b</p>');
    });
  });

  group('stripRubyXhtml', () {
    test('unwraps publisher ruby to base text', () {
      final result = stripRubyXhtml(
        chapter('<p>これは<ruby>既存<rt>きそん</rt></ruby>です</p>'),
      );
      expect(result, isNotNull);
      expect(result, contains('これは既存です'));
      expect(result, isNot(contains('<rt>')));
    });

    test('returns null when there is no ruby', () {
      expect(stripRubyXhtml(chapter('<p>なにもない</p>')), isNull);
    });
  });

  group('annotateXhtml', () {
    test('rewrites kanji text and survives html entities', () async {
      final generator = FuriganaGenerator(
        _FakeTokenizer({
          '今日\u00a0&明日': [_tok('今日', 'キョウ', 0)],
        }),
      );
      final result = await annotateXhtml(
        chapter('<p>今日&nbsp;&amp;明日</p>'),
        generator,
      );
      expect(result, isNotNull);
      expect(result, contains('<ruby>今日<rt>きょう</rt></ruby>'));
      // The nbsp must round-trip as a real character, not a mangled
      // "&amp;nbsp;" literal, and the ampersand must stay escaped.
      expect(result, contains('\u00a0'));
      expect(result, isNot(contains('&amp;nbsp;')));
      expect(result, contains('&amp;'));
    });

    test('returns null on unparseable input', () async {
      final generator = FuriganaGenerator(_FakeTokenizer(const {}));
      expect(await annotateXhtml('<p>今日<broken', generator), isNull);
    });

    test('stripRubyWhere unwraps matching authored ruby, keeps the rest', () async {
      final generator = FuriganaGenerator(_FakeTokenizer(const {}));
      final result = await annotateXhtml(
        chapter(
          '<p><ruby>今日<rt>きょう</rt></ruby>は'
          '<ruby>鬱<rt>うつ</rt></ruby>だ</p>',
        ),
        generator,
        stripRubyWhere: authoredRubyStripFor(FuriganaMode.aboveLevel, 3),
      );
      // Strip-only change (no annotations) must still rewrite the entry.
      expect(result, isNotNull);
      expect(result, contains('今日は'));
      expect(result, isNot(contains('<rt>きょう</rt>')));
      expect(result, contains('<ruby>鬱<rt>うつ</rt></ruby>'));
    });
  });

  group('buildFuriganaEpub', () {
    test('mode all annotates chapters, preserves other entries', () async {
      final path = await writeEpub(buildTestEpub(chapter('<p>今日</p>')));
      final generator = FuriganaGenerator(
        _FakeTokenizer({
          '今日': [_tok('今日', 'キョウ', 0)],
        }),
      );

      final out = await buildFuriganaEpub(
        path,
        mode: FuriganaMode.all,
        generator: generator,
      );

      expect(out, isNotNull);
      final decoded = ZipDecoder().decodeBytes(out!);
      expect(decoded.files.first.name, 'mimetype');
      expect(decoded.files.first.compression, CompressionType.none);
      final chapterOut = utf8.decode(
        decoded.findFile('OEBPS/chapter1.xhtml')!.readBytes()!,
      );
      expect(chapterOut, contains('<ruby>今日<rt>きょう</rt></ruby>'));
      expect(decoded.findFile('OEBPS/image.png')!.readBytes(), _imageBytes);
      expect(
        utf8.decode(decoded.findFile('OEBPS/style.css')!.readBytes()!),
        'body{}',
      );
    });

    test('mode book returns the original bytes untouched', () async {
      final bytes = buildTestEpub(chapter('<p>今日</p>'));
      final path = await writeEpub(bytes);

      final out = await buildFuriganaEpub(path, mode: FuriganaMode.book);

      expect(out, bytes);
    });

    test('mode hide strips all ruby', () async {
      final path = await writeEpub(
        buildTestEpub(chapter('<p><ruby>既存<rt>きそん</rt></ruby>と今日</p>')),
      );

      final out = await buildFuriganaEpub(path, mode: FuriganaMode.hide);

      final chapterOut = utf8.decode(
        ZipDecoder()
            .decodeBytes(out!)
            .findFile('OEBPS/chapter1.xhtml')!
            .readBytes()!,
      );
      expect(chapterOut, isNot(contains('<rt>')));
      expect(chapterOut, contains('既存と今日'));
    });

    test('aboveLevel strips known authored ruby, annotates hard bare '
        'kanji, keeps hard authored ruby', () async {
      final path = await writeEpub(
        buildTestEpub(
          chapter(
            '<p><ruby>今日<rt>きょう</rt></ruby>の'
            '<ruby>鬱<rt>うつ</rt></ruby>と憂鬱</p>',
          ),
        ),
      );
      const level = 3;
      final generator = FuriganaGenerator(
        _FakeTokenizer({
          '今日': [_tok('今日', 'キョウ', 0)],
          'と憂鬱': [_tok('と', 'ト', 0), _tok('憂鬱', 'ユウウツ', 1)],
        }),
        skipToken: (t) => !wordNeedsFuriganaAboveLevel(t.surface, level),
      );

      final out = await buildFuriganaEpub(
        path,
        mode: FuriganaMode.aboveLevel,
        generator: generator,
        stripRubyWhere: authoredRubyStripFor(FuriganaMode.aboveLevel, level),
      );

      final chapterOut = utf8.decode(
        ZipDecoder()
            .decodeBytes(out!)
            .findFile('OEBPS/chapter1.xhtml')!
            .readBytes()!,
      );
      // N5 authored ruby unwrapped and not re-annotated.
      expect(chapterOut, isNot(contains('<rt>きょう</rt>')));
      expect(chapterOut, contains('今日の'));
      // N1 authored ruby untouched (its reading wins over MeCab's).
      expect(chapterOut, contains('<ruby>鬱<rt>うつ</rt></ruby>'));
      // N1 bare text still gets generated ruby.
      expect(chapterOut, contains('<ruby>憂鬱<rt>ゆううつ</rt></ruby>'));
    });

    test('returns null when the tokenizer cannot come up', () async {
      final path = await writeEpub(buildTestEpub(chapter('<p>今日</p>')));
      final generator = FuriganaGenerator(
        _FakeTokenizer(const {}, ready: false),
      );

      expect(
        await buildFuriganaEpub(
          path,
          mode: FuriganaMode.all,
          generator: generator,
        ),
        isNull,
      );
    });

    test(
      'malformed chapter is copied unmodified and export continues',
      () async {
        final path = await writeEpub(buildTestEpub('<p>今日<broken'));
        final generator = FuriganaGenerator(
          _FakeTokenizer({
            '今日': [_tok('今日', 'キョウ', 0)],
          }),
        );

        final out = await buildFuriganaEpub(
          path,
          mode: FuriganaMode.all,
          generator: generator,
        );

        expect(out, isNotNull);
        final chapterOut = utf8.decode(
          ZipDecoder()
              .decodeBytes(out!)
              .findFile('OEBPS/chapter1.xhtml')!
              .readBytes()!,
        );
        expect(chapterOut, '<p>今日<broken');
      },
    );
  });
}
