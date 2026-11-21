import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/file_pick.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:path/path.dart' as p;

import '../../shared/file_dialog_fakes.dart';

/// The two backup kinds must never be confused: a zip handed to the reading
/// data importer is rejected by kind, with a message that names the other
/// button, instead of a generic parse error. `pickReadingDataBackup` is the
/// gate the import goes through.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  File? picked;

  const zipSignature = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00];

  String encodedManifest() => BackupSerializer.encode(
    BackupManifest(
      version: BackupManifest.currentVersion,
      createdAt: DateTime.utc(2026, 9, 7),
      settings: const BackupSettings(app: {}, reader: {}),
      savedWords: const [],
      books: const [],
    ),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_kind_');
    picked = null;
    fakeFilePicker((_) => [?picked?.path]);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('importBackupFile', () {
    test('a zip file is reported as the full backup kind', () async {
      final zip = File(p.join(tempDir.path, 'mekuru-full-backup.zip'));
      await zip.writeAsBytes(zipSignature);

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
      await file.writeAsString(encodedManifest());

      final manifest = await BackupFileManager().importBackupFile(file.path);
      expect(manifest.version, 1);
    });
  });

  group('pickReadingDataBackup', () {
    test('is cancelled when the picker is dismissed', () async {
      expect(
        await BackupFileManager.pickReadingDataBackup(),
        isA<FileDialogCancelled<List<String>>>(),
      );
    });

    test('rejects a zip by its bytes, whatever it is called', () async {
      final zip = File(p.join(tempDir.path, 'renamed.mekuru'));
      await zip.writeAsBytes(zipSignature);
      picked = zip;

      await expectLater(
        BackupFileManager.pickReadingDataBackup(),
        throwsA(
          isA<WrongBackupKindException>().having(
            (e) => e.found,
            'found',
            BackupKind.full,
          ),
        ),
      );
    });

    test('rejects any other non-.mekuru file as a format error', () async {
      final text = File(p.join(tempDir.path, 'notes.txt'));
      await text.writeAsString('hello');
      picked = text;

      await expectLater(
        BackupFileManager.pickReadingDataBackup(),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('hands back a .mekuru file untouched', () async {
      final file = File(p.join(tempDir.path, 'manual_backup.mekuru'));
      await file.writeAsString(encodedManifest());
      picked = file;

      expect(
        await BackupFileManager.pickReadingDataBackup(),
        isA<FileDialogDone<List<String>>>().having((r) => r.value, 'value', [
          file.path,
        ]),
      );
    });
  });

  test('BackupKind.isZipSignature recognises only the zip magic', () {
    expect(BackupKind.isZipSignature([0x50, 0x4B, 0x03, 0x04]), isTrue);
    expect(BackupKind.isZipSignature('{"version":1}'.codeUnits), isFalse);
    expect(BackupKind.isZipSignature([0x50, 0x4B]), isFalse);
  });
}
