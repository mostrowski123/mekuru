import 'dart:convert';
import 'dart:io';

/// Atomic file-write helpers.
///
/// A plain `writeAsString`/`writeAsBytes` that is interrupted mid-write (app
/// killed, disk full) leaves a truncated file at the destination. These
/// helpers write to a `<path>.tmp` sibling first and then rename it over the
/// destination, so the destination only ever contains the old contents or the
/// complete new contents.
///
/// Rename is atomic on POSIX filesystems (Android); on Windows Dart's
/// `File.rename` replaces an existing destination, which keeps tests portable.
Future<void> writeBytesAtomic(File file, List<int> bytes) async {
  final tmp = File('${file.path}.tmp');
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  } catch (_) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {
      // Best-effort cleanup; the original error matters more.
    }
    rethrow;
  }
}

/// String variant of [writeBytesAtomic].
Future<void> writeStringAtomic(
  File file,
  String contents, {
  Encoding encoding = utf8,
}) => writeBytesAtomic(file, encoding.encode(contents));
