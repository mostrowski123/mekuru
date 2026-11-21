import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

/// Whether a model's download (`runDownload`) finished in [dir]. The marker
/// doesn't say which pin it was for, so a pin with a new name has to clear the
/// old one first (see `dropOlderWordAudioPin`).
Future<bool> modelFilesInstalled(Directory dir) =>
    File(p.join(dir.path, modelInstalledMarker)).exists();

/// A downloaded model file did not match its pinned size and sha256.
class ModelVerificationException extends FileSystemException {
  const ModelVerificationException() : super('Model file failed verification');
}

// A function of its own, so the isolate takes nothing along but [path]: a
// closure sent to an isolate carries everything its function's closures
// capture, and a caller's closure could take its HttpClient along, which can't
// be sent.
/// The file's sha256, hashed off the UI isolate: models run to gigabytes.
Future<String> fileSha256(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);
