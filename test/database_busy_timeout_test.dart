import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Regression tests for MEKURU-1C: a transient `database is locked`
/// (SQLITE_BUSY) during the very first open — drift caches the failed lazy
/// open, so one transient lock used to kill all DB access for the session.
/// `PRAGMA busy_timeout` makes cross-process contention wait instead of
/// throwing; these tests pin the pragma and its production wiring.
///
/// Deliberately NOT tested with a competing in-process lock: POSIX lock
/// semantics make SQLite's busy handler unreliable for same-process
/// conflicts (such a test passes on Windows and fails on Linux CI), and
/// cross-process contention — the real MEKURU-1C shape — is SQLite's own
/// documented busy_timeout behavior, not our code.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  test('setupNativeConnection applies a 5s busy_timeout', () {
    final raw = sqlite.sqlite3.openInMemory();
    addTearDown(raw.close);

    AppDatabase.setupNativeConnection(raw);

    expect(raw.select('PRAGMA busy_timeout').single['timeout'], 5000);
  });

  test(
    'the production connection wires the busy timeout (MEKURU-1C)',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('mekuru_busy_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

      // Default constructor → _openConnection(): the real wiring, including
      // the setup callback that must apply the pragma.
      final db = AppDatabase();
      addTearDown(db.close);

      final row = await db.customSelect('PRAGMA busy_timeout').getSingle();
      expect(row.data['timeout'], 5000);
    },
  );
}
