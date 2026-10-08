import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/user_font_store.dart';
import 'package:path/path.dart' as p;

const _ttf = [0x00, 0x01, 0x00, 0x00, 0x00, 0x0A];

void main() {
  group('detectFontFormat', () {
    test('names each supported format by its first four bytes', () {
      expect(detectFontFormat(_ttf), FontFileFormat.trueType);
      expect(detectFontFormat('true....'.codeUnits), FontFileFormat.trueType);
      expect(detectFontFormat('OTTO....'.codeUnits), FontFileFormat.openType);
      expect(detectFontFormat('wOFF....'.codeUnits), FontFileFormat.woff);
      expect(detectFontFormat('wOF2....'.codeUnits), FontFileFormat.woff2);
    });

    test('refuses collections, other files and short reads', () {
      Matcher refused(UserFontImportError error) => throwsA(
        isA<UserFontImportException>().having((e) => e.error, 'error', error),
      );
      expect(
        () => detectFontFormat('ttcf....'.codeUnits),
        refused(UserFontImportError.collection),
      );
      expect(
        () => detectFontFormat([0x50, 0x4B, 0x03, 0x04]), // a zip
        refused(UserFontImportError.notAFont),
      );
      expect(
        () => detectFontFormat([0x00, 0x01]),
        refused(UserFontImportError.notAFont),
      );
    });
  });

  group('safeFontBaseName', () {
    test('keeps readable names, Japanese included', () {
      expect(safeFontBaseName('游明朝 Bold'), '游明朝 Bold');
      expect(
        safeFontBaseName('Noto Serif JP (Regular)'),
        'Noto Serif JP (Regular)',
      );
    });

    test('replaces characters that break paths and trims leading dots', () {
      expect(safeFontBaseName('a:b?c*"d<e>f|g'), 'a_b_c__d_e_f_g');
      expect(safeFontBaseName('..hidden'), 'hidden');
      expect(safeFontBaseName('dir/name'), 'dir_name');
      expect(safeFontBaseName('...'), 'font');
      expect(safeFontBaseName(''), 'font');
    });
  });

  group('UserFontStore', () {
    late Directory root;
    late Directory source;
    late UserFontStore store;

    File sourceFile(String name, List<int> bytes) =>
        File(p.join(source.path, name))..writeAsBytesSync(bytes);

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fonts_root_');
      source = await Directory.systemTemp.createTemp('fonts_src_');
      store = UserFontStore(root: () async => root);
    });

    tearDown(() async {
      await root.delete(recursive: true);
      await source.delete(recursive: true);
    });

    test('an empty store lists nothing', () async {
      expect(await store.list(), isEmpty);
    });

    test(
      'imports a font under its own name with the detected extension',
      () async {
        final font = await store.import(sourceFile('游明朝 Bold.TTF', _ttf).path);

        expect(font.fileName, '游明朝 Bold.ttf');
        expect(font.displayName, '游明朝 Bold');
        expect(await store.list(), [font]);
        final stored = await store.fileFor(font.fileName);
        expect(stored!.readAsBytesSync(), _ttf);
      },
    );

    test('a woff2 named .ttf is stored as .woff2', () async {
      final font = await store.import(
        sourceFile('mislabelled.ttf', 'wOF2....'.codeUnits).path,
      );
      expect(font.fileName, 'mislabelled.woff2');
    });

    test('a second font with the same name gets a number', () async {
      await store.import(sourceFile('Mincho.ttf', _ttf).path);
      final second = await store.import(sourceFile('Mincho.ttf', _ttf).path);
      expect(second.fileName, 'Mincho (2).ttf');
      expect((await store.list()).map((f) => f.fileName), [
        'Mincho.ttf',
        'Mincho (2).ttf',
      ]);
    });

    test('refuses a zip renamed to .ttf and leaves nothing behind', () async {
      await expectLater(
        store.import(sourceFile('fake.ttf', [0x50, 0x4B, 0x03, 0x04]).path),
        throwsA(isA<UserFontImportException>()),
      );
      expect(await store.list(), isEmpty);
    });

    test('refuses a font over the size cap before copying', () async {
      final big = File(p.join(source.path, 'big.ttf'));
      final raf = big.openSync(mode: FileMode.write)
        ..writeFromSync(_ttf)
        ..truncateSync(maxUserFontBytes + 1);
      raf.closeSync();

      await expectLater(
        store.import(big.path),
        throwsA(
          isA<UserFontImportException>().having(
            (e) => e.error,
            'error',
            UserFontImportError.tooLarge,
          ),
        ),
      );
      expect(
        Directory(p.join(root.path, UserFontStore.dirName)).existsSync(),
        isFalse,
      );
    });

    test('a half-copied .tmp file is never listed', () async {
      final dir = Directory(p.join(root.path, UserFontStore.dirName))
        ..createSync();
      File(p.join(dir.path, 'partial.ttf.tmp')).writeAsBytesSync(_ttf);
      expect(await store.list(), isEmpty);
    });

    test(
      'fileFor refuses names that leave the folder or are missing',
      () async {
        await store.import(sourceFile('Ok.ttf', _ttf).path);
        expect(await store.fileFor(null), isNull);
        expect(await store.fileFor('../Ok.ttf'), isNull);
        expect(await store.fileFor('Missing.ttf'), isNull);
        expect(await store.fileFor('Ok.ttf'), isNotNull);
      },
    );

    test('delete removes the font', () async {
      final font = await store.import(
        sourceFile('Gone.otf', 'OTTO....'.codeUnits).path,
      );
      await store.delete(font.fileName);
      expect(await store.list(), isEmpty);
    });
  });
}
