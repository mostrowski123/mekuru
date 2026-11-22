import 'dart:io';

/// Fills the install folder [path] through [fill], so that a failure leaves
/// [path] as it was. [fill] writes into the sibling `<path>.new`, which takes
/// the place of [path] only once [fill] has returned; an install already at
/// [path] stays whole until then. Its files are then deleted, never
/// rewritten, so a reader that holds them open (MeCab maps UniDic-lite's)
/// keeps reading the old ones.
///
/// Rename can't replace a folder that holds files, so the old one moves to
/// `<path>.old` first, on Android, iOS and Windows alike. What a killed app
/// left is cleared by the next fill: `<path>.new` goes, and an install a
/// killed swap had moved to `<path>.old` comes back.
Future<T> fillInstallFolder<T>(
  String path,
  Future<T> Function(String dir) fill,
) async {
  final target = Directory(path);
  final next = Directory('$path.new');
  final old = Directory('$path.old');
  Future<void> bringBackOld() async {
    if (!target.existsSync() && old.existsSync()) await old.rename(path);
  }

  await bringBackOld();
  for (final leftover in [next, old]) {
    if (leftover.existsSync()) await leftover.delete(recursive: true);
  }
  await next.create(recursive: true);
  try {
    final result = await fill(next.path);
    if (target.existsSync()) await target.rename(old.path);
    await next.rename(path);
    try {
      if (old.existsSync()) await old.delete(recursive: true);
    } on FileSystemException {
      // The next fill clears it.
    }
    return result;
  } catch (_) {
    try {
      await bringBackOld();
      if (next.existsSync()) await next.delete(recursive: true);
    } on FileSystemException {
      // The next fill clears it; the caller hears the cause.
    }
    rethrow;
  }
}
