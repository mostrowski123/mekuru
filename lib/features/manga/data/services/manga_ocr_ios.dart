import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'manga_ocr_algorithms.dart';
import 'model_download.dart';
import 'ndl_ocr_algorithms.dart';
import 'ndl_text_model.dart';
import 'vision_block_grouping.dart';

/// The same manga-ocr files Android downloads (its `manifest.json`; a test
/// keeps the two in step), without the GPL comic-text-detector: iOS finds text
/// with Apple Vision.
const List<ModelFile> mangaOcrIosModelFiles = [
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
  static const _maxLineChars = 14;
  // [PAD], [UNK], [CLS], [SEP], [MASK]
  static const _specialTokens = 5;

  List<String>? _vocab;

  Future<Directory> _dir() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'manga_ocr_models'),
  );

  Future<bool> get installed async => modelFilesInstalled(await _dir());

  /// Downloads and verifies every file, then marks the pack installed.
  /// [onProgress] is the fraction of all bytes. An interrupted download keeps
  /// its partial file, and the next one resumes it. With [wifiOnly] the
  /// download stops with [WifiLostException] when the network stops being
  /// Wi-Fi.
  Future<void> download({
    void Function(double)? onProgress,
    bool wifiOnly = false,
  }) async {
    final dir = await (await _dir()).create(recursive: true);
    // Re-downloadable, so kept out of iCloud and device backups.
    await _storage.invokeMethod('excludeFromBackup', [dir.path]);
    await downloadModelFiles(
      dir,
      mangaOcrIosModelFiles,
      onProgress: onProgress,
      wifiOnly: wifiOnly,
    );
  }

  Future<void> remove() async {
    // Not while a block is being read.
    await _oneAtATime(() => _channel.invokeMethod<void>('mangaOcrUnload'));
    _vocab = null;
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// manga-ocr's reading of each block, split back onto the block's lines,
  /// or null when there is nothing to read with or anything fails: the
  /// caller then keeps Vision's own text.
  ///
  /// A block with a line too long for manga-ocr keeps Vision's lines, except
  /// that with [ndlModelDir] (the NDL text-line model, `ndl_text_model.dart`)
  /// each long line is read by NDL. Tadoku graded readers, 20 pages: 8.3% of
  /// characters wrong with Vision's lines, 4.2% with NDL's. NDL works without
  /// the manga-ocr pack; the other blocks then keep Vision's text.
  Future<List<List<String>>?> readBlocks(
    Uint8List imageBytes,
    List<VisionBlock> blocks, {
    String? ndlModelDir,
  }) async {
    try {
      final useNdl = ndlModelDir != null && blocks.any(_hasLongLine);
      final useMangaOcr = blocks.isNotEmpty && await installed;
      if (!useMangaOcr && !useNdl) return null;
      final dir = (await _dir()).path;
      final vocab = useMangaOcr
          ? _vocab ??= await File(p.join(dir, 'vocab.txt')).readAsLines()
          : null;
      final models = {
        'encoder': p.join(dir, 'encoder_model_fp16.onnx'),
        'decoder': p.join(dir, 'decoder_model_int8.onnx'),
      };

      // Decoded by ImageIO on the CPU, not dart:ui, which may need the GPU:
      // iOS refuses that while a scan runs in the background.
      final page = await _channel.invokeMapMethod<String, Object?>(
        'decodeRgba',
        imageBytes,
      );
      if (page == null) return null;
      final width = page['width'] as int;
      final height = page['height'] as int;
      final rgba = page['rgba'] as Uint8List;

      final out = <List<String>>[];
      for (final block in blocks) {
        final visionLines = [for (final l in block.lines) l.text];
        // The crop is squashed to 224x224, so past 14 characters a line has
        // under 16 px per character and the reading falls apart. Manga columns
        // stay shorter (5 of 2211 Manga109-s blocks, which Vision reads a
        // little better anyway); a text page's do not (Tadoku graded readers:
        // 77% of characters wrong, Vision's own text 8%).
        if (_hasLongLine(block)) {
          out.add([
            for (final line in block.lines)
              ndlModelDir != null && _isLong(line.text)
                  ? await _readLineWithNdl(
                      ndlModelDir,
                      line,
                      rgba,
                      width,
                      height,
                    )
                  : line.text,
          ]);
          continue;
        }
        if (vocab == null) {
          out.add(visionLines);
          continue;
        }
        final whole = await _read(
          models,
          OcrPixels.modelInput(
            rgba,
            width,
            height,
            left: block.left.floor(),
            top: block.top.floor(),
            right: block.right.ceil(),
            bottom: block.bottom.ceil(),
          ),
          vocab,
        );
        // An empty reading is a failed one; Vision's text is better than none.
        out.add(
          whole.isEmpty ? visionLines : splitAcrossLines(whole, visionLines),
        );
      }
      return out;
    } catch (e) {
      debugPrint('[MangaOcrIos] falling back to Vision text: $e');
      return null;
    }
  }

  static bool _isLong(String line) => line.runes.length > _maxLineChars;

  static bool _hasLongLine(VisionBlock block) =>
      block.lines.any((l) => _isLong(l.text));

  /// NDL's reading of one line (its Vision box, no padding: padding hurt),
  /// cleaned like manga-ocr's, or Vision's text when NDL fails or reads
  /// nothing.
  Future<String> _readLineWithNdl(
    String dir,
    VisionLine line,
    Uint8List rgba,
    int width,
    int height,
  ) async {
    try {
      final pixels = NdlPixels.modelInput(
        rgba,
        width,
        height,
        left: line.left.floor(),
        top: line.top.floor(),
        right: line.right.ceil(),
        bottom: line.bottom.ceil(),
      );
      final charset = _ndlCharsets[dir] ??= parseNdlCharset(
        await File(_ndlFile(dir, '.yaml')).readAsString(),
      );
      final out = await _oneAtATime(() async {
        await _channel.invokeMethod('ndlLoad', _ndlFile(dir, '.onnx'));
        return _channel.invokeMapMethod<String, Object?>('ndlRun', pixels);
      });
      // manga-ocr's text conventions (no whitespace, ASCII full width), as
      // Android does.
      final text = MangaOcrDecode.postProcess(
        ndlDecode(
          out!['logits'] as Float32List,
          out['steps'] as int,
          out['classes'] as int,
          charset,
        ),
      );
      if (text.isNotEmpty) return text;
    } catch (e) {
      debugPrint('[MangaOcrIos] NDL failed, keeping Vision text: $e');
    }
    return line.text;
  }

  /// Parsed once per model directory.
  final _ndlCharsets = <String, List<String>>{};

  static String _ndlFile(String dir, String extension) => p.join(
    dir,
    ndlTextModelFiles.firstWhere((f) => f.name.endsWith(extension)).name,
  );

  /// Frees the NDL session, before its files are removed.
  Future<void> unloadNdl() async {
    await _oneAtATime(() => _channel.invokeMethod<void>('ndlUnload'));
    _ndlCharsets.clear();
  }

  /// The native model keeps one encoder output, which every decode step
  /// reads. Two scans (two books) read blocks at the same time, so each
  /// block's load, encode and decode steps take one turn here, and another
  /// read's encode can't land in the middle of them.
  Future<void> _turn = Future.value();

  Future<T> _oneAtATime<T>(Future<T> Function() action) {
    final result = _turn.then((_) => action());
    _turn = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _read(
    Map<String, String> models,
    Float32List pixels,
    List<String> vocab,
  ) async {
    final ids = await _oneAtATime(() async {
      await _channel.invokeMethod('mangaOcrLoad', models);
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
      return ids;
    });
    final text = StringBuffer();
    for (final id in ids) {
      if (id < _specialTokens || id >= vocab.length) continue;
      final token = vocab[id];
      text.write(token.startsWith('##') ? token.substring(2) : token);
    }
    return MangaOcrDecode.postProcess(text.toString());
  }
}
