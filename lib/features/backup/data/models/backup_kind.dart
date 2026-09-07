/// The two backup kinds Mekuru writes. They must never be confused: a
/// reading data backup (`.mekuru`, JSON, merges) and a full backup (`.zip`,
/// replaces everything in Mekuru on the device).
enum BackupKind {
  readingData,
  full;

  /// True for the local-file-header signature every zip archive starts with.
  static bool isZipSignature(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;
}

/// The user picked the other kind of backup for this importer.
class WrongBackupKindException implements Exception {
  /// What the picked file actually is.
  final BackupKind found;

  const WrongBackupKindException(this.found);

  @override
  String toString() => 'Wrong backup kind: file is a ${found.name} backup';
}
