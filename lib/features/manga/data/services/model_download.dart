import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart'
    show downloadResumable;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One file of a downloadable model (OCR, translation), pinned by size and
/// sha256.
typedef ModelFile = ({String name, String url, int bytes, String sha256});

/// The file in a model's folder that says it finished.
const modelInstalledMarker = 'INSTALLED';

/// The download size of [files] for display, e.g. "42.6 MB".
String modelFilesSize(List<ModelFile> files) =>
    '${(files.fold<int>(0, (a, f) => a + f.bytes) / 1000000).toStringAsFixed(1)} MB';

/// The folder for an optional download called [name], kept out of device
/// backups because it can be downloaded again. On Android that is
/// `noBackupFilesDir`, like the manga-ocr models: the app support directory is
/// `Context.filesDir`, and `no_backup` sits next to it. iOS flags the directory
/// instead ([excludeFromIosBackup]).
Future<String> noBackupModelDir(String name) async {
  final support = (await getApplicationSupportDirectory()).path;
  final root = defaultTargetPlatform == TargetPlatform.iOS
      ? support
      : p.join(p.dirname(support), 'no_backup');
  return p.join(root, name);
}

/// Whether [downloadModelFiles] finished in [dir]. The marker doesn't say which
/// pin it was for, so a pin with a new name has to clear the old one first (see
/// `dropOlderWordAudioPin`).
Future<bool> modelFilesInstalled(Directory dir) =>
    File(p.join(dir.path, modelInstalledMarker)).exists();

/// Downloads and verifies every one of [files] into the existing [dir], then
/// marks it installed. [onProgress] is the fraction of all bytes. An
/// interrupted download keeps its partial file, and the next one resumes it.
/// With [wifiOnly] the download stops with [WifiLostException] when the
/// network stops being Wi-Fi. Closing [client] with `force: true` stops it too;
/// it serves one file, and is closed when that ends.
Future<void> downloadModelFiles(
  Directory dir,
  List<ModelFile> files, {
  void Function(double)? onProgress,
  bool wifiOnly = false,
  HttpClient? client,
}) => _downloads[dir.path] ??=
    _download(
      dir,
      files,
      onProgress: onProgress,
      wifiOnly: wifiOnly,
      client: client,
    ).whenComplete(() {
      _downloads.remove(dir.path);
    });

/// Downloads running, by folder. A second call for the same folder (a tile
/// built again after the user left Downloads and came back, or the Sentence
/// tab and Downloads both fetching a translation pair) joins the first
/// rather than write the same partial files; it gets no progress meanwhile.
final _downloads = <String, Future<void>>{};

Future<void> _download(
  Directory dir,
  List<ModelFile> files, {
  void Function(double)? onProgress,
  bool wifiOnly = false,
  HttpClient? client,
}) async {
  final total = files.fold<int>(0, (a, f) => a + f.bytes);
  var done = 0;
  // At most once per whole percent: a socket chunk is far smaller than the
  // progress a listener can show.
  var lastPercent = -1;
  void report(int bytes) {
    final percent = bytes * 100 ~/ total;
    if (percent == lastPercent) return;
    lastPercent = percent;
    onProgress?.call(bytes / total);
  }

  for (final file in files) {
    final target = File(p.join(dir.path, file.name));
    if (!await _matches(target, file)) {
      final partial = '${target.path}.part';
      final fileClient = client ?? HttpClient();
      Future<void> fetch() => downloadResumable(
        file.url,
        partial,
        client: fileClient,
        // GitHub gzips text files: the body would then outgrow its
        // Content-Length once unzipped, and a byte range would count
        // compressed bytes. The pinned sizes and hashes are of the file.
        headers: const {HttpHeaders.acceptEncodingHeader: 'identity'},
        onProgress: (received, _) => report(done + received),
      );
      try {
        await (wifiOnly ? whileOnWifi(fileClient, fetch) : fetch());
      } finally {
        fileClient.close(force: true);
      }
      if (!await _matches(File(partial), file)) {
        await File(partial).delete();
        throw const ModelVerificationException();
      }
      await File(partial).rename(target.path);
    }
    done += file.bytes;
    report(done);
  }
  await File(p.join(dir.path, modelInstalledMarker)).writeAsString('ok');
}

/// A downloaded model file did not match its pinned size and sha256.
class ModelVerificationException extends FileSystemException {
  const ModelVerificationException() : super('Model file failed verification');
}

Future<bool> _matches(File file, ModelFile expected) async {
  if (!await file.exists() || await file.length() != expected.bytes) {
    return false;
  }
  return await fileSha256(file.path) == expected.sha256;
}

// A function of its own, so the isolate takes nothing along but [path]: a
// closure sent to an isolate carries everything its function's closures
// capture, and a caller's closure could take its HttpClient along, which can't
// be sent.
/// The file's sha256, hashed off the UI isolate: models run to gigabytes.
Future<String> fileSha256(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);
