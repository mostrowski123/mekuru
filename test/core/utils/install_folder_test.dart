import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/utils/install_folder.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String install;

  setUp(() {
    root = Directory.systemTemp.createTempSync('install_folder_');
    install = p.join(root.path, 'unidic-lite');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void write(String dir, String name, String text) => File(p.join(dir, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  /// Every file under the root, relative to it, with its text.
  Map<String, String> files() => {
    for (final f in root.listSync(recursive: true).whereType<File>())
      p.relative(f.path, from: root.path).replaceAll(r'\', '/'): f
          .readAsStringSync(),
  };

  Future<void> diskFull(String dir) async {
    write(dir, 'sys.dic', 'NEW');
    throw FileSystemException(
      'Write failed',
      p.join(dir, 'matrix.bin'),
      const OSError('No space left on device', 28),
    );
  }

  test(
    'a fill that fails partway, as on a full disk, leaves nothing',
    () async {
      await expectLater(
        fillInstallFolder(install, diskFull),
        throwsA(isA<FileSystemException>()),
      );

      expect(root.listSync(), isEmpty);
    },
  );

  test(
    'an install already there stays as it was when the fill fails',
    () async {
      write(install, 'sys.dic', 'OLD');
      write(install, '.install_complete', '{}');

      await expectLater(
        fillInstallFolder(install, diskFull),
        throwsA(isA<FileSystemException>()),
      );

      expect(files(), {
        'unidic-lite/sys.dic': 'OLD',
        'unidic-lite/.install_complete': '{}',
      });
    },
  );

  test('a fill that works replaces the install whole', () async {
    write(install, 'sys.dic', 'OLD');
    write(install, 'gone.dic', 'OLD');

    final result = await fillInstallFolder(install, (dir) async {
      write(dir, 'sys.dic', 'NEW');
      return 7;
    });

    expect(result, 7);
    expect(files(), {'unidic-lite/sys.dic': 'NEW'});
  });

  test('what a killed fill left goes, and the next fill works', () async {
    write('$install.new', 'stale.dic', 'HALF');

    await fillInstallFolder(install, (dir) async => write(dir, 'a', 'NEW'));

    expect(files(), {'unidic-lite/a': 'NEW'});
  });

  test('an install that a swap killed between its two renames had moved '
      'aside comes back', () async {
    // The app died after the old install moved aside and before the new one
    // took its place: both are whole, neither is in place.
    write('$install.old', '.install_complete', '{}');
    write('$install.new', '.install_complete', '{}');
    write('$install.new', 'sys.dic', 'NEW');

    await expectLater(
      fillInstallFolder(install, diskFull),
      throwsA(isA<FileSystemException>()),
    );

    expect(files(), {'unidic-lite/.install_complete': '{}'});
  });

  test('an old copy the app was killed deleting never comes back', () async {
    // The swap was done and the new install has since been deleted: what is
    // left of the old copy is its marker and half its files.
    write('$install.old', '.install_complete', '{}');
    write('$install.old', 'char.bin', 'HALF');

    await expectLater(
      fillInstallFolder(install, diskFull),
      throwsA(isA<FileSystemException>()),
    );

    expect(root.listSync(), isEmpty);
  });

  group('before a download asks how much room there is', () {
    test('a half unpack with no marker, and what a killed download left '
        'beside it, are freed', () async {
      // What 1.74.5 left when an unpack stopped on a full disk.
      write(install, 'sys.dic', 'HALF');
      write('$install.new', 'sys.dic', 'HALF');
      write('$install.old', 'char.bin', 'HALF');

      await clearInstallLeftovers(install, marker: '.install_complete');

      expect(root.listSync(), isEmpty);
    });

    test('a whole install stays, and only what is beside it goes', () async {
      write(install, 'sys.dic', 'OLD');
      write(install, '.install_complete', '{}');
      write('$install.new', 'sys.dic', 'HALF');

      await clearInstallLeftovers(install, marker: '.install_complete');

      expect(files(), {
        'unidic-lite/sys.dic': 'OLD',
        'unidic-lite/.install_complete': '{}',
      });
    });

    test('an install a killed swap had moved aside comes back and '
        'stays', () async {
      write('$install.old', '.install_complete', '{}');
      write('$install.new', 'sys.dic', 'NEW');

      await clearInstallLeftovers(install, marker: '.install_complete');

      expect(files(), {'unidic-lite/.install_complete': '{}'});
    });
  });

  test('deleting an install deletes what a download left beside it', () async {
    write(install, '.install_complete', '{}');
    write('$install.new', 'sys.dic', 'HALF');
    write('$install.old', 'char.bin', 'HALF');

    expect(await deleteInstallFolder(install), isTrue);

    expect(root.listSync(), isEmpty);
    expect(await deleteInstallFolder(install), isFalse);
  });
}
