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

  test('an install a killed swap had moved aside comes back', () async {
    write('$install.old', '.install_complete', '{}');

    await expectLater(
      fillInstallFolder(install, diskFull),
      throwsA(isA<FileSystemException>()),
    );

    expect(files(), {'unidic-lite/.install_complete': '{}'});
  });
}
