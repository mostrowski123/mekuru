import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/main.dart' as app show main;
import 'package:path/path.dart' as p;

import 'shared/test_infrastructure.dart';
import 'test_helpers.dart';

/// Plants a junk-filled orphan whose name-embedded timestamp is far older
/// than the sweep's default age gate.
Future<Directory> _plantAncientOrphan(String name) async {
  final root = await appBooksDir();
  final dir = Directory(p.join(root.path, name));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'junk.bin')).writeAsBytes([1, 2, 3]);
  return dir;
}

Future<List<String>> _trashEntryNames() async {
  final root = await appBooksDir();
  final trash = Directory(p.join(root.path, '.trash'));
  if (!await trash.exists()) return const [];
  return trash.list().map((e) => p.basename(e.path)).toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orphan_sweep_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await cleanupAppBooksDir();
  });

  testWidgets('sweep quarantines a planted orphan and spares a real import', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = BookRepository(db);

    final fixturePath = await writeFixtureEpub(tempDir, title: '走れメロス');
    final imported = await repo.importEpub(fixturePath);
    final orphan = await _plantAncientOrphan('book_1000_deadbeef');

    final swept = await repo.sweepOrphanImportDirs();

    expect(swept, 1);
    expect(await orphan.exists(), isFalse);
    expect(await _trashEntryNames(), [
      matches(RegExp(r'^\d+_book_1000_deadbeef$')),
    ]);
    expect(await Directory(imported.filePath).exists(), isTrue);

    // The imported book still renders in the library after the sweep.
    await tester.pumpWidget(
      buildIntegrationTestApp(db: db, home: const LibraryScreen()),
    );
    await pumpUntilVisible(tester, find.text('走れメロス'));
    expect(find.text('走れメロス'), findsAtLeastNWidgets(1));
  });

  testWidgets('a sweep racing a live import on the real FS never breaks it', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = BookRepository(db);

    // A completed import first — with an empty table the sweep refuses to
    // run at all (that guard has its own test below).
    final seedPath = await writeFixtureEpub(
      Directory(p.join(tempDir.path, 'seed'))..createSync(),
      title: '三四郎',
    );
    await repo.importEpub(seedPath);

    final fixturePath = await writeFixtureEpub(tempDir, title: 'こころ');
    final orphan = await _plantAncientOrphan('manga_2000');

    final importing = repo.importEpub(fixturePath);
    final sweeping = repo.sweepOrphanImportDirs(minAge: Duration.zero);

    final imported = await importing;
    await sweeping;

    expect(BookRepository.inFlightImportDirNames, isEmpty);
    expect(await Directory(imported.filePath).exists(), isTrue);
    expect(await orphan.exists(), isFalse);
  });

  testWidgets('quarantined entries expire after the retention window', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = BookRepository(db);

    final fixturePath = await writeFixtureEpub(tempDir, title: '坊っちゃん');
    await repo.importEpub(fixturePath);
    await _plantAncientOrphan('book_3000_cafebabe');

    expect(await repo.sweepOrphanImportDirs(), 1);
    final entry = (await _trashEntryNames()).single;

    // Backdate the quarantine timestamp past the retention window.
    final root = await appBooksDir();
    final trashPath = p.join(root.path, '.trash');
    await Directory(
      p.join(trashPath, entry),
    ).rename(p.join(trashPath, '1000_book_3000_cafebabe'));
    // A fresh quarantine entry must survive the same sweep.
    final keepName =
        '${DateTime.now().millisecondsSinceEpoch}_book_4000_feedface';
    await Directory(p.join(trashPath, keepName)).create();

    await repo.sweepOrphanImportDirs();

    expect(await _trashEntryNames(), [keepName]);
  });

  testWidgets('the real startup hook sweeps orphans and spares live books', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = BookRepository(db);

    final fixturePath = await writeFixtureEpub(tempDir, title: '銀河鉄道の夜');
    final imported = await repo.importEpub(fixturePath);
    final orphan = await _plantAncientOrphan('manga_5000');

    await tester.pumpWidget(buildIntegrationTestRealApp(db: db));
    await pumpUntilVisible(
      tester,
      find.byType(NavigationBar),
      timeout: const Duration(seconds: 15),
    );

    // The sweep is fire-and-forget from the post-frame callback — poll.
    var sweptByStartup = false;
    for (var tick = 0; tick < 60; tick++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (!await orphan.exists()) {
        sweptByStartup = true;
        break;
      }
    }

    expect(sweptByStartup, isTrue, reason: 'startup hook never swept');
    expect(await _trashEntryNames(), [matches(RegExp(r'^\d+_manga_5000$'))]);
    expect(await Directory(imported.filePath).exists(), isTrue);
    await pumpUntilVisible(tester, find.text('銀河鉄道の夜'));
  });

  testWidgets('a real boot with an empty database never sweeps', (
    tester,
  ) async {
    // Empty table + files on disk can mean the DB was lost while the books
    // survived — the sweep must refuse to treat anything as an orphan.
    final orphan = await _plantAncientOrphan('book_6000_0badf00d');

    await app.main();
    await pumpUntilVisible(
      tester,
      find.byType(NavigationBar),
      timeout: const Duration(seconds: 30),
    );
    // Give the fire-and-forget sweep ample time to have run.
    for (var tick = 0; tick < 8; tick++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(await orphan.exists(), isTrue);
    expect(await _trashEntryNames(), isEmpty);
  });
}
