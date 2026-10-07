import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart'
    show downloadResumable;
import 'package:path/path.dart' as p;

/// One file of a downloadable model (OCR, translation), pinned by size and
/// sha256.
typedef ModelFile = ({String name, String url, int bytes, String sha256});

const _marker = 'INSTALLED';

/// The download size of [files] for display, e.g. "42.6 MB".
String modelFilesSize(List<ModelFile> files) =>
    '${(files.fold<int>(0, (a, f) => a + f.bytes) / 1000000).toStringAsFixed(1)} MB';

/// Whether [downloadModelFiles] finished in [dir].
Future<bool> modelFilesInstalled(Directory dir) =>
    File(p.join(dir.path, _marker)).exists();

/// Downloads and verifies every one of [files] into the existing [dir], then
/// marks it installed. [onProgress] is the fraction of all bytes. An
/// interrupted download keeps its partial file, and the next one resumes it.
/// With [wifiOnly] the download stops with [WifiLostException] when the
/// network stops being Wi-Fi.
Future<void> downloadModelFiles(
  Directory dir,
  List<ModelFile> files, {
  void Function(double)? onProgress,
  bool wifiOnly = false,
}) => _downloads[dir.path] ??=
    _download(
      dir,
      files,
      onProgress: onProgress,
      wifiOnly: wifiOnly,
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
}) async {
  final total = files.fold<int>(0, (a, f) => a + f.bytes);
  var done = 0;
  for (final file in files) {
    final target = File(p.join(dir.path, file.name));
    if (!await _matches(target, file)) {
      final partial = '${target.path}.part';
      final client = HttpClient();
      Future<void> fetch() => downloadResumable(
        file.url,
        partial,
        client: client,
        // GitHub gzips text files: the body would then outgrow its
        // Content-Length once unzipped, and a byte range would count
        // compressed bytes. The pinned sizes and hashes are of the file.
        headers: const {HttpHeaders.acceptEncodingHeader: 'identity'},
        onProgress: (received, _) =>
            onProgress?.call((done + received) / total),
      );
      try {
        await (wifiOnly ? whileOnWifi(client, fetch) : fetch());
      } finally {
        client.close(force: true);
      }
      if (!await _matches(File(partial), file)) {
        await File(partial).delete();
        throw const FileSystemException('Model file failed verification');
      }
      await File(partial).rename(target.path);
    }
    done += file.bytes;
    onProgress?.call(done / total);
  }
  await File(p.join(dir.path, _marker)).writeAsString('ok');
}

/// Hashed off the UI isolate: model files run to tens of MB.
Future<bool> _matches(File file, ModelFile expected) async {
  if (!await file.exists() || await file.length() != expected.bytes) {
    return false;
  }
  final path = file.path;
  return await Isolate.run(() => _sha256Of(path)) == expected.sha256;
}

Future<String> _sha256Of(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
