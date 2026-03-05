import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:mekuru/features/backup/data/models/backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/backup_serializer.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Info about a backup file on disk.
class BackupFileInfo {
  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final int sizeBytes;
  final bool isAuto;

  const BackupFileInfo({
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
    required this.isAuto,
  });
}

/// Handles reading/writing/listing/pruning backup files on disk.
class BackupFileManager {
  static const String _backupDirName = 'backups';
  static const String _autoPrefix = 'auto_';
  static const String _manualPrefix = 'manual_';
  static const String _extension = '.mekuru';
  static const int maxAutoBackups = 5;

  /// Creates a backup file and returns its path.
  Future<File> createBackupFile(
    BackupManifest manifest, {
    bool isAuto = false,
  }) async {
    final dir = await _getBackupDirectory();
    final prefix = isAuto ? _autoPrefix : _manualPrefix;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final fileName = '${prefix}backup_$timestamp$_extension';
    final file = File(path.join(dir.path, fileName));

    final json = BackupSerializer.encode(manifest);
    await file.writeAsString(json);

    if (isAuto) {
      await _pruneOldAutoBackups(dir);
    }

    return file;
  }

  /// Lists all available backup files, sorted newest first.
  Future<List<BackupFileInfo>> listBackups() async {
    final dir = await _getBackupDirectory();
    if (!dir.existsSync()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(_extension))
        .toList();

    final infos = <BackupFileInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      final name = path.basename(file.path);
      infos.add(
        BackupFileInfo(
          filePath: file.path,
          fileName: name,
          createdAt: stat.modified,
          sizeBytes: stat.size,
          isAuto: name.startsWith(_autoPrefix),
        ),
      );
    }

    infos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return infos;
  }

  /// Reads and parses a backup file.
  Future<BackupManifest> readBackupFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw BackupFormatException('File not found: $filePath');
    }
    final content = await file.readAsString();
    return BackupSerializer.decode(content);
  }

  /// Exports a backup file by letting the user choose a save location.
  /// Returns `true` if the file was saved, `false` if cancelled.
  Future<bool> exportBackupFile(String filePath) async {
    final sourceFile = File(filePath);
    final fileName = path.basename(filePath);
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Backup',
      fileName: fileName,
      bytes: await sourceFile.readAsBytes(),
    );
    return outputPath != null;
  }

  /// Copies an external backup file (from file picker) to the backup directory
  /// and parses it.
  Future<BackupManifest> importBackupFile(String externalPath) async {
    final file = File(externalPath);
    final content = await file.readAsString();
    return BackupSerializer.decode(content);
  }

  /// Deletes a backup file.
  Future<void> deleteBackupFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _getBackupDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final backupDir = Directory(path.join(appDir.path, _backupDirName));
    if (!backupDir.existsSync()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<void> _pruneOldAutoBackups(Directory dir) async {
    final autoFiles = dir
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              path.basename(f.path).startsWith(_autoPrefix) &&
              f.path.endsWith(_extension),
        )
        .toList();

    if (autoFiles.length <= maxAutoBackups) return;

    // Sort oldest first
    autoFiles.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );

    final toDelete = autoFiles.sublist(0, autoFiles.length - maxAutoBackups);
    for (final file in toDelete) {
      await file.delete();
    }
  }
}
