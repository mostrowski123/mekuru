import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';

import '../../shared/test_database.dart';

void main() {
  FullBackupManifest sample({int? format, int? schemaVersion}) =>
      FullBackupManifest(
        format: format ?? FullBackupManifest.currentFormat,
        appVersion: '1.38.0',
        schemaVersion: schemaVersion ?? AppDatabase.latestSchemaVersion,
        createdAt: DateTime.utc(2026, 9, 7, 12, 30),
        appSupportPath: '/data/user/0/moe.matthew.mekuru/files',
        bookCount: 3,
        dictionaryCount: 2,
        externalMangaCount: 1,
        dbBytes: 1000,
        booksBytes: 5000,
        entryCount: 42,
      );

  test('round-trips through JSON', () {
    final original = sample();
    final decoded = FullBackupManifest.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.toJson(), original.toJson());
    expect(decoded.createdAt, original.createdAt);
    expect(decoded.bookCount, 3);
    expect(decoded.dictionaryCount, 2);
    expect(decoded.externalMangaCount, 1);
    expect(decoded.totalBytes, 6000);
  });

  test('latestSchemaVersion is the live Drift schema version', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, AppDatabase.latestSchemaVersion);
  });

  test('a newer archive format is rejected with the producing app version', () {
    expect(
      () => FullBackupManifest.fromJson(sample(format: 2).toJson()),
      throwsA(
        isA<FullBackupTooNewException>().having(
          (e) => e.appVersion,
          'appVersion',
          '1.38.0',
        ),
      ),
    );
  });

  test('a newer database schema is rejected', () {
    expect(
      () => FullBackupManifest.fromJson(
        sample(schemaVersion: AppDatabase.latestSchemaVersion + 1).toJson(),
      ),
      throwsA(isA<FullBackupTooNewException>()),
    );
  });

  test('an older database schema is accepted (Drift migrates it)', () {
    final decoded = FullBackupManifest.fromJson(
      sample(schemaVersion: AppDatabase.latestSchemaVersion - 3).toJson(),
    );
    expect(decoded.schemaVersion, AppDatabase.latestSchemaVersion - 3);
  });

  test('unknown keys are ignored and missing counts default to zero', () {
    final json = sample().toJson()
      ..['somethingFromTheFuture'] = true
      ..remove('externalMangaCount')
      ..remove('dictionaryCount');
    final decoded = FullBackupManifest.fromJson(json);
    expect(decoded.externalMangaCount, 0);
    expect(decoded.dictionaryCount, 0);
  });

  test('missing required fields are a format error, not a crash', () {
    expect(
      () => FullBackupManifest.fromJson(<String, dynamic>{'format': 1}),
      throwsA(isA<FullBackupFormatException>()),
    );
  });

  test('entry names are the fixed archive contract', () {
    expect(FullBackupManifest.manifestEntry, 'manifest.json');
    expect(FullBackupManifest.settingsEntry, 'settings.mekuru');
    expect(FullBackupManifest.databaseEntry, 'mekuru_db.sqlite');
    expect(FullBackupManifest.booksPrefix, 'books/');
  });
}
