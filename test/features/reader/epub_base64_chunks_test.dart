import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

void main() {
  test('decoded chunks concatenate back into the original bytes', () async {
    // 14 bytes arriving in uneven stream events (like File.openRead blocks);
    // chunkSize 6 → re-chunked into 6, 6, 2 (last one partial).
    final bytes = List.generate(14, (i) => (i * 37) % 256);
    final events = Stream.fromIterable([
      bytes.sublist(0, 4),
      bytes.sublist(4, 11),
      bytes.sublist(11),
    ]);

    final chunks = await epubBase64Chunks(events, chunkSize: 6).toList();

    expect(chunks.length, 3);
    expect(base64Decode(chunks[0]).length, 6);
    expect(base64Decode(chunks[1]).length, 6);
    // Mirror the JS side: decode each chunk independently, then concatenate.
    final reassembled = chunks.expand(base64Decode).toList();
    expect(reassembled, bytes);
  });

  test('empty input yields no chunks', () async {
    expect(await epubBase64Chunks(const Stream.empty()).toList(), isEmpty);
  });
}
