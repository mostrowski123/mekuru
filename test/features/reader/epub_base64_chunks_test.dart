import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

void main() {
  test('decoded chunks concatenate back into the original bytes', () {
    // 14 bytes with chunkSize 6 → chunks of 6, 6, 2 (last one partial).
    final bytes = Uint8List.fromList(List.generate(14, (i) => (i * 37) % 256));

    final chunks = epubBase64Chunks(bytes, chunkSize: 6).toList();

    expect(chunks.length, 3);
    // Mirror the JS side: decode each chunk independently, then concatenate.
    final reassembled = chunks.expand(base64Decode).toList();
    expect(reassembled, bytes);
  });

  test('empty input yields no chunks', () {
    expect(epubBase64Chunks(Uint8List(0)), isEmpty);
  });
}
