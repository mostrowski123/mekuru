import 'dart:io';

import 'package:path/path.dart' as p;

/// Fills the install folder [path] through [fill], so that a failure leaves
/// [path] as it was. [fill] writes into the sibling `<path>.new`, which takes
/// the place of [path] only once [fill] has returned; an install already at
/// [path] stays whole until then. Its files are then deleted, never
/// rewritten, so a reader that holds them open (MeCab maps UniDic-lite's)
/// keeps reading the old ones.
///
/// Rename can't replace a folder that holds files, so the old one moves to
/// `<path>.old` first, on Android, iOS and Windows alike. What a killed app
/// left is cleared by the next fill ([_clearSiblings]).
Future<T> fillInstallFolder<T>(
  String path,
  Future<T> Function(String dir) fill,
) async {
  final target = Directory(path);
  final next = Directory('$path.new');
  final old = Directory('$path.old');

  await _clearSiblings(path);
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
      await _clearSiblings(path);
    } on FileSystemException {
      // The next fill clears it; the caller hears the cause.
    }
    rethrow;
  }
}

/// Frees what earlier downloads into [path] left, before the next one asks
/// how much room there is: the folders beside it, and [path] itself unless
/// it holds the file [marker]. A folder with no marker is an unpack that
/// stopped halfway (1.74.5 left those in place): no install, and up to all
/// of an install's size.
Future<void> clearInstallLeftovers(
  String path, {
  required String marker,
}) async {
  await _clearSiblings(path);
  final target = Directory(path);
  if (target.existsSync() && !File(p.join(path, marker)).existsSync()) {
    await target.delete(recursive: true);
  }
}

/// Deletes the install at [path] with what a download left beside it.
/// Whether there was a folder at [path].
Future<bool> deleteInstallFolder(String path) async {
  final target = Directory(path);
  final existed = target.existsSync();
  for (final dir in [target, Directory('$path.new'), Directory('$path.old')]) {
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
  return existed;
}

/// Clears `<path>.new` and `<path>.old`. With nothing at [path] and both of
/// them there, a swap stopped between its two renames, and the install it
/// had moved aside comes back first. An `.old` on its own is a copy the app
/// was killed deleting, which may be half gone: it never comes back.
Future<void> _clearSiblings(String path) async {
  final next = Directory('$path.new');
  final old = Directory('$path.old');
  if (!Directory(path).existsSync() && next.existsSync() && old.existsSync()) {
    await old.rename(path);
  }
  for (final leftover in [next, old]) {
    if (leftover.existsSync()) await leftover.delete(recursive: true);
  }
}
