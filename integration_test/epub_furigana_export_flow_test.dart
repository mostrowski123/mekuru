import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

/// Integration test for the furigana EPUB export pipeline.
///
/// Unit tests cover the XHTML rewriting with a fake tokenizer; this test
/// exercises the real path used by the export action on device: MeCab init →
/// MecabService.runOffIsolate worker → buildFuriganaEpubForMode → zip out.
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
    '</manifest>'
    '<spine><itemref idref="c1"/></spine></package>';

String _chapter(String body) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!DOCTYPE html>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
    '<body>$body</body></html>';

Uint8List _buildEpub(String chapterXhtml) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..addFile(
      ArchiveFile.bytes('META-INF/container.xml', utf8.encode(_containerXml)),
    )
    ..addFile(ArchiveFile.bytes('OEBPS/content.opf', utf8.encode(_contentOpf)))
    ..addFile(
      ArchiveFile.bytes('OEBPS/chapter1.xhtml', utf8.encode(chapterXhtml)),
    );
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await MecabService.instance.init();
  });

  Future<String> writeEpub(String body) async {
    final tempDir = await Directory.systemTemp.createTemp('export_flow_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final path = '${tempDir.path}/book.epub';
    await File(path).writeAsBytes(_buildEpub(_chapter(body)));
    return path;
  }

  String chapterOut(Uint8List epubBytes) {
    final decoded = ZipDecoder().decodeBytes(epubBytes);
    expect(decoded.files.first.name, 'mimetype');
    expect(decoded.files.first.compression, CompressionType.none);
    return utf8.decode(decoded.findFile('OEBPS/chapter1.xhtml')!.readBytes()!);
  }

  test('mode all annotates via the runOffIsolate worker', () async {
    final path = await writeEpub('<p>今日は晴れだ。</p>');

    final bytes = await MecabService.instance.runOffIsolate(
      () =>
          buildFuriganaEpubForMode(path, mode: FuriganaMode.all, jlptLevel: 3),
    );

    expect(bytes, isNotNull);
    final xhtml = chapterOut(bytes!);
    expect(xhtml, contains('<ruby>今日<rt>きょう</rt></ruby>'));
    expect(xhtml, contains('<rt>'));
  });

  test('mode aboveLevel keeps easy words bare, annotates hard ones', () async {
    final path = await writeEpub('<p>今日は憂鬱だ。</p>');

    final bytes = await MecabService.instance.runOffIsolate(
      () => buildFuriganaEpubForMode(
        path,
        mode: FuriganaMode.aboveLevel,
        jlptLevel: 3,
      ),
    );

    expect(bytes, isNotNull);
    final xhtml = chapterOut(bytes!);
    // 憂 is N1 → the whole word gets ruby; 今日 is N5 kanji → stays bare.
    expect(xhtml, contains('<ruby>憂鬱<rt>ゆううつ</rt></ruby>'));
    expect(xhtml, isNot(contains('<ruby>今日')));
    expect(xhtml, contains('今日'));
  });
}
