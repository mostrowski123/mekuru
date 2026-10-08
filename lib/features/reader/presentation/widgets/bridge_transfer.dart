import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Re-chunks [bytes] into base64 chunks for transfer to the JS bridge.
///
/// [chunkSize] must be a multiple of 3 so every chunk encodes without
/// padding and the independently decoded chunks concatenate back into the
/// original bytes. Stream event boundaries are arbitrary (e.g. the 64 KiB
/// blocks of `File.openRead`); every yielded chunk except the last holds
/// exactly [chunkSize] bytes. Each `yield` suspends the source stream, so
/// only about one chunk is ever resident at a time.
Stream<String> epubBase64Chunks(
  Stream<List<int>> bytes, {
  int chunkSize = 3 * 1024 * 1024,
}) async* {
  assert(chunkSize > 0 && chunkSize % 3 == 0);
  final buffer = BytesBuilder(copy: false);
  await for (final data in bytes) {
    buffer.add(data);
    while (buffer.length >= chunkSize) {
      final buffered = buffer.takeBytes();
      yield base64Encode(Uint8List.sublistView(buffered, 0, chunkSize));
      // sublist (not sublistView): a view would pin the whole chunk-sized
      // backing array for the life of the small tail.
      buffer.add(buffered.sublist(chunkSize));
    }
  }
  if (buffer.isNotEmpty) yield base64Encode(buffer.takeBytes());
}

/// Streams [file] to the bridge in bounded base64 chunks, never inlined
/// whole (that OOMs on large books, MEKURU-1B): [begin] (given the byte
/// length) has the bridge preallocate its buffer, then [append] receives
/// each chunk. False as soon as the web view goes away, so a reader left
/// mid-transfer neither keeps encoding nor loads a truncated buffer.
Future<bool> sendFileToBridge(
  File file, {
  required String Function(int length) begin,
  required String append,
  required Future<bool> Function(String source) run,
}) async {
  if (!await run(begin(await file.length()))) return false;
  await for (final chunk in epubBase64Chunks(file.openRead())) {
    if (!await run("$append('$chunk')")) return false;
  }
  return true;
}

/// An added font and the CSS family it is registered under in the bridge.
typedef UserFontSend = ({File file, String family});

/// Sends an added font to the bridge as CSS family [family].
Future<bool> sendUserFont(
  File file,
  String family,
  Future<bool> Function(String source) run,
) => sendFileToBridge(
  file,
  begin: (length) => 'beginFontTransfer($length, ${jsonEncode(family)})',
  append: 'appendFontChunk',
  run: run,
);
