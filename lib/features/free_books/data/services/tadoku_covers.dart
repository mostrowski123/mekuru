import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:mekuru/core/services/download_to_file.dart';
import 'package:path/path.dart' as p;

/// Graded-reader covers, each downloaded once into a folder and kept there,
/// named after its URL (a new cover is a new file). tadoku.org limits
/// request rates, and scrolling the grid asks for dozens of covers at once,
/// so at most [maxParallel] download at a time, a cover already on its way
/// is never asked for again, and one that failed waits [retryAfter] before
/// another try.
class TadokuCovers {
  TadokuCovers(
    this._dir, {
    this.maxParallel = 2,
    this.retryAfter = const Duration(minutes: 1),
    Future<void> Function(Uri url, String path)? fetch,
    DateTime Function()? now,
  }) : _fetch = fetch ?? ((url, path) => downloadToFile('$url', path)),
       _now = now ?? DateTime.now;

  final Future<Directory> _dir;
  final int maxParallel;
  final Duration retryAfter;
  final Future<void> Function(Uri url, String path) _fetch;
  final DateTime Function() _now;

  final _pending = <Uri, Future<File>>{};
  final _failedAt = <Uri, DateTime>{};
  final _queue = Queue<Completer<void>>();
  var _running = 0;

  /// [url]'s cover on disk, downloaded first unless it already is.
  Future<File> cover(Uri url) => _pending[url] ??= _load(url).whenComplete(() {
    // A block: returning the removed future would make this one wait on
    // itself.
    _pending.remove(url);
  });

  Future<File> _load(Uri url) async {
    final file = File(p.join((await _dir).path, url.pathSegments.last));
    if (await file.exists()) return file;
    final failed = _failedAt[url];
    if (failed != null && _now().difference(failed) < retryAfter) {
      throw StateError('The cover failed to download moments ago');
    }
    await _takeTurn();
    try {
      await file.parent.create(recursive: true);
      // Into place only once complete, so a half-written cover never shows.
      final part = '${file.path}.part';
      await _fetch(url, part);
      await File(part).rename(file.path);
      _failedAt.remove(url);
      return file;
    } catch (_) {
      _failedAt[url] = _now();
      rethrow;
    } finally {
      _endTurn();
    }
  }

  Future<void> _takeTurn() async {
    if (_running < maxParallel) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _queue.add(turn);
    await turn.future; // The download ending hands over its turn.
  }

  void _endTurn() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _running--;
    }
  }
}
