import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:path/path.dart' as p;

/// The two backup kinds must never be confused: a zip handed to the reading
/// data importer is rejected by kind, with a message that names the other
/// button, instead of a generic parse error.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_kind_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('a zip file is reported as the full backup kind', () async {
    final zip = File(p.join(tempDir.path, 'mekuru-full-backup.zip'));
    // Local file header signature, as every zip starts.
    await zip.writeAsBytes([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00]);

    await expectLater(
      BackupFileManager().importBackupFile(zip.path),
      throwsA(
        isA<WrongBackupKindException>().having(
          (e) => e.found,
          'found',
          BackupKind.full,
        ),
      ),
    );
  });

  test('a reading data backup still decodes', () async {
    final file = File(p.join(tempDir.path, 'manual_backup.mekuru'));
    await file.writeAsString(
      BackupSerializer.encode(
        BackupManifest(
          version: BackupManifest.currentVersion,
          createdAt: DateTime.utc(2026, 9, 7),
          settings: const BackupSettings(app: {}, reader: {}),
          savedWords: const [],
          books: const [],
        ),
      ),
    );

    final manifest = await BackupFileManager().importBackupFile(file.path);
    expect(manifest.version, 1);
  });

  test('BackupKind.isZipSignature recognises only the zip magic', () {
    expect(BackupKind.isZipSignature([0x50, 0x4B, 0x03, 0x04]), isTrue);
    expect(BackupKind.isZipSignature('{"version":1}'.codeUnits), isFalse);
    expect(BackupKind.isZipSignature([0x50, 0x4B]), isFalse);
  });
}
