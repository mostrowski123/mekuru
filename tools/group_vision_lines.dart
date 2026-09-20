// Runs the app's own Vision line grouping over a dump made by
// `tools/vision_recall.swift --images-from`, so benchmarks score exactly the
// code that ships:
//   dart run tools/group_vision_lines.dart lines.json blocks.json
import 'dart:convert';
import 'dart:io';

import 'package:mekuru/features/manga/data/services/vision_block_grouping.dart';

void main(List<String> args) {
  final pages = jsonDecode(File(args[0]).readAsStringSync()) as List;
  final out = [
    for (final page in pages)
      {
        'path': page['path'],
        'blocks': [
          for (final block in groupVisionLines([
            for (final l in page['lines'] as List)
              VisionLine(
                left: (l['box'][0] as num).toDouble(),
                top: (l['box'][1] as num).toDouble(),
                right: (l['box'][2] as num).toDouble(),
                bottom: (l['box'][3] as num).toDouble(),
                text: l['text'] as String,
              ),
          ]))
            {
              'box': [block.left, block.top, block.right, block.bottom],
              'vertical': block.vertical,
              'lines': [for (final l in block.lines) l.text],
            },
        ],
      },
  ];
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
