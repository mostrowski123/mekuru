import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_file_manager.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:path/path.dart' as p;

/// Returns whatever file the test scripted, standing in for the system
/// picker behind `BackupFileManager.pickBackupFile`.
class _FakeFilePicker extends FilePickerPlatform {
  PlatformFile? file;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    final picked = file;
    return picked == null ? null : FilePickerResult([picked]);
  }
}

/// The two backup kinds must never be confused: a zip handed to the reading
/// data importer is rejected by kind, with a message that names the other
/// button, instead of a generic parse error. `pickReadingDataBackup` is the
/// one gate both import entry points (screen and notifier) go through.
void main() {
  late Directory tempDir;
  late _FakeFilePicker picker;
  late FilePickerPlatform originalPicker;

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

  PlatformFile platformFile(File file) =>
      PlatformFile(name: p.basename(file.path), size: 0, path: file.path);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_kind_');
    originalPicker = FilePickerPlatform.instance;
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() async {
    FilePickerPlatform.instance = originalPicker;
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
    test('returns null when the picker is dismissed', () async {
      picker.file = null;
      expect(await BackupFileManager.pickReadingDataBackup(), isNull);
    });

    test('rejects a zip by its bytes, whatever it is called', () async {
      final zip = File(p.join(tempDir.path, 'renamed.mekuru'));
      await zip.writeAsBytes(zipSignature);
      picker.file = platformFile(zip);

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
      picker.file = platformFile(text);

      await expectLater(
        BackupFileManager.pickReadingDataBackup(),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('hands back a .mekuru file untouched', () async {
      final file = File(p.join(tempDir.path, 'manual_backup.mekuru'));
      await file.writeAsString(encodedManifest());
      picker.file = platformFile(file);

      final picked = await BackupFileManager.pickReadingDataBackup();
      expect(picked?.path, file.path);
    });
  });

  test('BackupKind.isZipSignature recognises only the zip magic', () {
    expect(BackupKind.isZipSignature([0x50, 0x4B, 0x03, 0x04]), isTrue);
    expect(BackupKind.isZipSignature('{"version":1}'.codeUnits), isFalse);
    expect(BackupKind.isZipSignature([0x50, 0x4B]), isFalse);
  });
}
