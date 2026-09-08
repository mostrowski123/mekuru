import 'dart:io';

/// Where a full backup export is written. The app uses a SAF folder the
/// user picked; tests and any non-SAF fallback use a plain file path.
sealed class FullBackupTarget {
  const FullBackupTarget();

  const factory FullBackupTarget.tree(String treeUri) = FullBackupTreeTarget;
  const factory FullBackupTarget.file(String path) = FullBackupFileTarget;
}

final class FullBackupTreeTarget extends FullBackupTarget {
  final String treeUri;
  const FullBackupTreeTarget(this.treeUri);
}

final class FullBackupFileTarget extends FullBackupTarget {
  final String path;
  const FullBackupFileTarget(this.path);
}

/// Where a full backup is read from during import.
sealed class FullBackupSource {
  const FullBackupSource();

  const factory FullBackupSource.uri(String uri, {required int sizeBytes}) =
      FullBackupUriSource;

  const factory FullBackupSource.file(String path) = FullBackupFileSource;

  /// Archive size, used as the extraction progress total.
  int get sizeBytes;

  /// The source as the native side opens it (`content://` or `file://`).
  String get uriString;
}

final class FullBackupUriSource extends FullBackupSource {
  final String uri;
  @override
  final int sizeBytes;

  const FullBackupUriSource(this.uri, {required this.sizeBytes});

  @override
  String get uriString => uri;
}

final class FullBackupFileSource extends FullBackupSource {
  final String path;
  const FullBackupFileSource(this.path);

  @override
  int get sizeBytes {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }

  @override
  String get uriString => Uri.file(path).toString();
}
