import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mekuru/core/platform/ios_storage.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_download.dart';

const _ndlBase =
    'https://raw.githubusercontent.com/ndl-lab/ndlocr-lite/'
    '636d1cfeb1331f89f4048f416e49e23a09a714b5/src';

/// NDLOCR-Lite's 100-character PARSeq recognizer and the charset it decodes
/// with (`ndl_ocr_algorithms.dart`), pinned to one commit of
/// ndl-lab/ndlocr-lite (National Diet Library, CC BY 4.0).
const List<ModelFile> ndlTextModelFiles = [
  (
    name: 'parseq-ndl-24x768-100-tiny-153epoch-tegaki3-r8data-202604.onnx',
    url:
        '$_ndlBase/model/parseq-ndl-24x768-100-tiny-153epoch-tegaki3-r8data-202604.onnx',
    bytes: 42588187,
    sha256: '06462b0dbd5b0b8508545c8c3d485cf20dbf4ffa652fe145e69c9e7457080602',
  ),
  (
    name: 'NDLmoji.yaml',
    url: '$_ndlBase/config/NDLmoji.yaml',
    bytes: 42434,
    sha256: 'f6ad5a2de444b495155866af811cf1a98309dcae3225db802767ea531a2dc529',
  ),
];

/// The NDL text-line model that reads the long lines of scanned text pages,
/// on both platforms: installs, locates and removes its files.
class NdlTextModel {
  NdlTextModel._();
  static final NdlTextModel instance = NdlTextModel._();

  /// Where the files live, kept out of backups because they can be
  /// downloaded again. On Android that is `noBackupFilesDir`, like the
  /// manga-ocr models: the app support directory is `Context.filesDir`, and
  /// `no_backup` sits next to it. iOS flags the directory instead.
  Future<String> get path async {
    final support = (await getApplicationSupportDirectory()).path;
    final root = defaultTargetPlatform == TargetPlatform.iOS
        ? support
        : p.join(p.dirname(support), 'no_backup');
    return p.join(root, 'ndl_text_model');
  }

  Future<bool> get installed async =>
      modelFilesInstalled(Directory(await path));

  /// Downloads and verifies every file, then marks the model installed.
  /// [onProgress] is the fraction of all bytes. An interrupted download keeps
  /// its partial file, and the next one resumes it. With [wifiOnly] the
  /// download stops with [WifiLostException] when the network stops being
  /// Wi-Fi.
  Future<void> download({
    void Function(double)? onProgress,
    bool wifiOnly = false,
  }) async {
    final dir = await Directory(await path).create(recursive: true);
    await excludeFromIosBackup([dir.path]);
    await downloadModelFiles(
      dir,
      ndlTextModelFiles,
      onProgress: onProgress,
      wifiOnly: wifiOnly,
    );
  }

  Future<void> remove() async {
    final dir = Directory(await path);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
