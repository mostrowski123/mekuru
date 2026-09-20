import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'manga_ocr_algorithms.dart';
import 'vision_block_grouping.dart';

/// One file of the manga-ocr model pack.
typedef MangaOcrModelFile = ({
  String name,
  String url,
  int bytes,
  String sha256,
});

/// The same manga-ocr files Android downloads (its `manifest.json`; a test
/// keeps the two in step), without the GPL comic-text-detector: iOS finds text
/// with Apple Vision.
const List<MangaOcrModelFile> mangaOcrIosModelFiles = [
  (
    name: 'encoder_model_fp16.onnx',
    url:
        'https://huggingface.co/onnx-community/manga-ocr-base-ONNX/resolve/f9023406bb2f6b17df67bc4a327c56ecd20611f0/onnx/encoder_model_fp16.onnx',
    bytes: 171851891,
    sha256: '1a6a57bc3608195c4577b13ac3aadab810dce42fa22c5a3acf0570bffc013b60',
  ),
  (
    name: 'decoder_model_int8.onnx',
    url:
        'https://huggingface.co/onnx-community/manga-ocr-base-ONNX/resolve/f9023406bb2f6b17df67bc4a327c56ecd20611f0/onnx/decoder_model_int8.onnx',
    bytes: 29627936,
    sha256: '2e7177d2b0a59f1c612b694ed70c13971bee765cc2b2bc7bc9376e4753652f27',
  ),
  (
    name: 'vocab.txt',
    url:
        'https://huggingface.co/kha-white/manga-ocr-base/resolve/aa6573bd10b0d446cbf622e29c3e084914df9741/vocab.txt',
    bytes: 24072,
    sha256: '344fbb6b8bf18c57839e924e2c9365434697e0227fac00b88bb4899b78aa594d',
  ),
];

/// manga-ocr on iOS: installs the model files and reads text blocks with them.
/// The model itself runs behind `mekuru/vision_ocr` (ONNX Runtime in
/// `AppDelegate.swift`); pixels, decoding and clean-up are
/// `manga_ocr_algorithms.dart`.
class MangaOcrIos {
  MangaOcrIos._();
  static final MangaOcrIos instance = MangaOcrIos._();

  static const _channel = MethodChannel('mekuru/vision_ocr');
  static const _storage = MethodChannel('mekuru/ios_storage');
  static const _marker = 'INSTALLED';
  // [PAD], [UNK], [CLS], [SEP], [MASK]
  static const _specialTokens = 5;

  List<String>? _vocab;

  Future<Directory> _dir() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'manga_ocr_models'),
  );

  Future<bool> get installed async =>
      File(p.join((await _dir()).path, _marker)).exists();

  /// Downloads and verifies every file, then marks the pack installed.
  /// [onProgress] is the fraction of all bytes.
  Future<void> download({void Function(double)? onProgress}) async {
    final dir = await (await _dir()).create(recursive: true);
    // Re-downloadable, so kept out of iCloud and device backups.
    await _storage.invokeMethod('excludeFromBackup', [dir.path]);
    final total = mangaOcrIosModelFiles.fold<int>(0, (a, f) => a + f.bytes);
    var done = 0;
    for (final file in mangaOcrIosModelFiles) {
      final target = File(p.join(dir.path, file.name));
      if (!await _matches(target, file)) {
        final partial = '${target.path}.part';
        await downloadToFile(
          file.url,
          partial,
          onProgress: (f) => onProgress?.call((done + f * file.bytes) / total),
        );
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

  Future<void> remove() async {
    await _channel.invokeMethod('mangaOcrUnload');
    _vocab = null;
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<bool> _matches(File file, MangaOcrModelFile expected) async {
    if (!await file.exists() || await file.length() != expected.bytes) {
      return false;
    }
    return (await sha256.bind(file.openRead()).first).toString() ==
        expected.sha256;
  }

  /// manga-ocr's reading of each block, split back onto the block's lines, or
  /// null when the models are not installed or anything fails: the caller
  /// then keeps Vision's own text.
  Future<List<List<String>>?> readBlocks(
    Uint8List imageBytes,
    List<VisionBlock> blocks,
  ) async {
    try {
      if (blocks.isEmpty || !await installed) return null;
      final dir = (await _dir()).path;
      final vocab = _vocab ??= await File(
        p.join(dir, 'vocab.txt'),
      ).readAsLines();
      await _channel.invokeMethod('mangaOcrLoad', {
        'encoder': p.join(dir, 'encoder_model_fp16.onnx'),
        'decoder': p.join(dir, 'decoder_model_int8.onnx'),
      });

      final codec = await ui.instantiateImageCodec(imageBytes);
      final image = (await codec.getNextFrame()).image;
      final rgba = (await image.toByteData())!.buffer.asUint8List();

      final out = <List<String>>[];
      for (final block in blocks) {
        final whole = await _read(
          OcrPixels.modelInput(
            rgba,
            image.width,
            image.height,
            left: block.left.floor(),
            top: block.top.floor(),
            right: block.right.ceil(),
            bottom: block.bottom.ceil(),
          ),
          vocab,
        );
        final visionLines = [for (final l in block.lines) l.text];
        // An empty reading is a failed one; Vision's text is better than none.
        out.add(
          whole.isEmpty ? visionLines : splitAcrossLines(whole, visionLines),
        );
      }
      image.dispose();
      return out;
    } catch (e) {
      debugPrint('[MangaOcrIos] falling back to Vision text: $e');
      return null;
    }
  }

  Future<String> _read(Float32List pixels, List<String> vocab) async {
    await _channel.invokeMethod('mangaOcrEncode', pixels);
    final ids = [MangaOcrDecode.bos];
    while (ids.length < MangaOcrDecode.maxTokens) {
      final logits = await _channel.invokeMethod<Float32List>(
        'mangaOcrStep',
        ids,
      );
      final next = MangaOcrDecode.next(logits!, ids);
      if (next == MangaOcrDecode.eos) break;
      ids.add(next);
    }
    final text = StringBuffer();
    for (final id in ids) {
      if (id < _specialTokens || id >= vocab.length) continue;
      final token = vocab[id];
      text.write(token.startsWith('##') ? token.substring(2) : token);
    }
    return MangaOcrDecode.postProcess(text.toString());
  }
}
