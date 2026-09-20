import 'package:flutter/services.dart';

import '../models/mokuro_models.dart';
import 'manga_ocr_client.dart';
import 'manga_ocr_ios.dart';
import 'vision_block_grouping.dart';

const _channel = MethodChannel('mekuru/vision_ocr');

/// On-device OCR for one manga page on iOS: Apple Vision finds and reads the
/// text lines (`AppDelegate.swift`), [groupVisionLines] turns them into
/// blocks. Same signature as [MangaOcrClient.processPage] so the page loop in
/// `ocr_background_worker.dart` can use either.
Future<OcrPageResult> recognizePageWithVision(
  Uint8List imageBytes,
  String filename, {
  String? jobId,
  int? pageIndex,
}) async {
  final Map<String, dynamic>? page;
  try {
    page = await _channel.invokeMapMethod<String, dynamic>(
      'recognizeLines',
      imageBytes,
    );
  } on PlatformException catch (e) {
    // The page loop's failure handling is written for server errors.
    throw OcrServerException(500, e.message ?? 'Text recognition failed.');
  }
  if (page == null) throw const OcrServerException(500, 'No result.');

  final blocks = groupVisionLines([
    for (final line in page['lines'] as List)
      VisionLine(
        left: (line['box'][0] as num).toDouble(),
        top: (line['box'][1] as num).toDouble(),
        right: (line['box'][2] as num).toDouble(),
        bottom: (line['box'][3] as num).toDouble(),
        text: line['text'] as String,
      ),
  ]);
  // Vision finds the text; manga-ocr reads it better (Manga109-s: 9.5% of
  // characters wrong against Vision's 15.6% on the same blocks). Without the
  // model pack this is null and Vision's own text stays.
  final readings = await MangaOcrIos.instance.readBlocks(imageBytes, blocks);
  return OcrPageResult(
    imgWidth: page['width'] as int,
    imgHeight: page['height'] as int,
    blocks: [
      for (final (i, block) in blocks.indexed)
        mokuroBlockFromVision(block, lines: readings?[i]),
    ],
  );
}

/// The cache's block shape: a box, and per line its text and corner points
/// (clockwise from top-left), which word tapping and highlights read.
/// [lines] replaces Vision's text line for line.
MokuroTextBlock mokuroBlockFromVision(
  VisionBlock block, {
  List<String>? lines,
}) => MokuroTextBlock(
  box: [block.left, block.top, block.right, block.bottom],
  vertical: block.vertical,
  fontSize: block.fontSize,
  linesCoords: [
    for (final l in block.lines)
      [
        [l.left, l.top],
        [l.right, l.top],
        [l.right, l.bottom],
        [l.left, l.bottom],
      ],
  ],
  lines: lines ?? [for (final l in block.lines) l.text],
);
