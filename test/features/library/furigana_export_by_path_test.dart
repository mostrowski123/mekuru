import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

/// The size of the chunks package:archive streams in. The export may hold
/// this much at once, never the book.
const _chunk = 1 << 20;

/// Records the largest single read and write of every file opened in its
/// zone: a phone's heap cannot be measured here, but a whole-book buffer
/// shows up as a whole-book read or write.
final class _IoRecorder extends IOOverrides {
  int largestRead = 0;
  int largestWrite = 0;

  @override
  File createFile(String path) => _RecordingFile(super.createFile(path), this);
}

class _RecordingFile implements File {
  _RecordingFile(this._file, this._io);

  final File _file;
  final _IoRecorder _io;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() async {
    final bytes = await _file.readAsBytes();
    _io.largestRead = max(_io.largestRead, bytes.length);
    return bytes;
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    _io.largestWrite = max(_io.largestWrite, bytes.length);
    return _file.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _RecordingRandomAccessFile(_file.openSync(mode: mode), _io);

  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      _file.createSync(recursive: recursive, exclusive: exclusive);

  @override
  Future<File> copy(String newPath) => _file.copy(newPath);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingRandomAccessFile implements RandomAccessFile {
  _RecordingRandomAccessFile(this._file, this._io);

  final RandomAccessFile _file;
  final _IoRecorder _io;

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    _io.largestRead = max(_io.largestRead, (end ?? buffer.length) - start);
    return _file.readIntoSync(buffer, start, end);
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    _io.largestWrite = max(_io.largestWrite, (end ?? buffer.length) - start);
    _file.writeFromSync(buffer, start, end);
  }

  @override
  int lengthSync() => _file.lengthSync();

  @override
  void setPositionSync(int position) => _file.setPositionSync(position);

  @override
  void closeSync() => _file.closeSync();

  @override
  Future<void> close() => _file.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An EPUB several chunks big: a chapter with ruby, plus incompressible
/// "images" both deflated and STORED, the two ways books carry them.
Uint8List _bigEpub(Random random) {
  Uint8List noise(int length) =>
      Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?><container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
            'version="3.0"><manifest><item id="c" href="c.xhtml" '
            'media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c"/></spine></package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/c.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
            '<p><ruby>既存<rt>きそん</rt></ruby></p></body></html>',
      ),
    )
    ..addFile(ArchiveFile.bytes('OEBPS/deflated.jpg', noise(3 * _chunk)))
    ..addFile(
      ArchiveFile.noCompress('OEBPS/stored.jpg', 3 * _chunk, noise(3 * _chunk)),
    );
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String bookPath;
  late Uint8List book;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('furigana_streaming_');
    book = _bigEpub(Random(1));
    bookPath = '${dir.path}/book.epub';
    await File(bookPath).writeAsBytes(book);
  });

  tearDownAll(() => dir.delete(recursive: true));

  for (final mode in [FuriganaMode.book, FuriganaMode.hide]) {
    test('${mode.name} export streams file to file: no read or write is '
        'book-sized', () async {
      final outPath = '${dir.path}/${mode.name}.epub';
      final io = _IoRecorder();

      final written = await IOOverrides.runWithIOOverrides(
        () => writeFuriganaEpub(bookPath, outPath, mode: mode),
        io,
      );

      expect(written, isTrue);
      expect(book.length, greaterThan(6 * _chunk));
      expect(io.largestRead, lessThanOrEqualTo(_chunk));
      expect(io.largestWrite, lessThanOrEqualTo(_chunk));

      final out = ZipDecoder().decodeBytes(File(outPath).readAsBytesSync());
      expect(out.files.first.name, 'mimetype');
      expect(out.files.first.compression, CompressionType.none);
      final source = ZipDecoder().decodeBytes(book);
      expect(
        [for (final f in out.files) (f.name, f.compression)],
        [for (final f in source.files) (f.name, f.compression)],
      );
      for (final name in ['OEBPS/deflated.jpg', 'OEBPS/stored.jpg']) {
        expect(out.findFile(name)!.content, source.findFile(name)!.content);
      }
      final chapter = utf8.decode(out.findFile('OEBPS/c.xhtml')!.content);
      expect(chapter.contains('<rt>'), mode == FuriganaMode.book);
    });
  }

  group('saveEpubElsewhere hands the save dialog a path, never bytes', () {
    const path = '/tmp/本 (furigana).epub';
    final calls = <(String, MethodCall)>[];
    Object? reply = true;

    setUp(() {
      calls.clear();
      reply = true;
      for (final name in ['mekuru/ios_files', 'mekuru/android_saf']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(name), (call) async {
              calls.add((name, call));
              return reply;
            });
      }
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      for (final name in ['mekuru/ios_files', 'mekuru/android_saf']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(name), null);
      }
    });

    test('iOS: the document picker moves the file out', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(await saveEpubElsewhere(path), isTrue);

      expect(calls, hasLength(1));
      final (channel, call) = calls.single;
      expect(channel, 'mekuru/ios_files');
      expect(call.method, 'exportFile');
      expect(call.arguments, path);
    });

    test('Android: the system save dialog streams a copy', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(await saveEpubElsewhere(path), isTrue);

      expect(calls, hasLength(1));
      final (channel, call) = calls.single;
      expect(channel, 'mekuru/android_saf');
      expect(call.method, 'saveDocument');
      expect(call.arguments, {
        'path': path,
        'name': '本 (furigana).epub',
        'mimeType': 'application/epub+zip',
      });
    });

    test('a cancelled dialog reads as not saved', () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        reply = false;
        expect(await saveEpubElsewhere(path), isFalse);
      }
    });
  });
}
