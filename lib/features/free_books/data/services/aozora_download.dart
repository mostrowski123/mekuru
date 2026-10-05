import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mekuru/core/services/http_transport.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/services/aozora_epub_builder.dart';

const _timeout = Duration(seconds: 30);

/// Fetches [work]'s XHTML from Aozora Bunko plus the images it shows, and
/// builds the EPUB off the calling isolate. [base] is where Aozora's card
/// folders live (tests point it at a local server).
///
/// Throws [NetworkException] when the connection fails and [HttpException]
/// when the page itself is missing; a missing image only falls back to its
/// alt text. [onProgress] gets the share of requests done (the page, then
/// each image), ending at 1.0 before the EPUB is built.
Future<Uint8List> fetchAozoraEpub(
  AozoraWork work,
  http.Client client, {
  String base = aozoraCardsBase,
  void Function(double progress)? onProgress,
}) async {
  final page = Uri.parse(base).resolve(work.xhtmlPath);
  final (xhtml, sources) = await _decode((await _get(client, page))!);
  var done = 1;
  onProgress?.call(done / (1 + sources.length));
  final images = <String, Uint8List>{};
  // A few at a time: each gaiji is tiny, but a work can show hundreds.
  for (var i = 0; i < sources.length; i += 4) {
    await Future.wait([
      for (final src in sources.skip(i).take(4))
        _get(client, page.resolve(src), allowMissing: true).then((bytes) {
          if (bytes != null) images[src] = bytes;
          onProgress?.call(++done / (1 + sources.length));
        }),
    ]);
  }
  return _build(xhtml, work, images);
}

// The isolate jobs live in functions of their own: a closure sent to an
// isolate takes along everything its function's closures capture, and
// [fetchAozoraEpub]'s capture onProgress, which holds the app's state.

/// Shift_JIS decoding of a big novel takes tens of milliseconds.
Future<(String, List<String>)> _decode(Uint8List bytes) => Isolate.run(() {
  final xhtml = decodeAozoraXhtml(bytes);
  return (xhtml, aozoraImageSources(xhtml));
});

Future<Uint8List> _build(
  String xhtml,
  AozoraWork work,
  Map<String, Uint8List> images,
) => Isolate.run(
  () => buildAozoraEpub(xhtml: xhtml, work: work, images: images),
);

Future<Uint8List?> _get(
  http.Client client,
  Uri uri, {
  bool allowMissing = false,
}) async {
  final response = await sendWithTimeout(
    client,
    http.Request('GET', uri),
    timeout: _timeout,
  );
  if (response.statusCode == HttpStatus.ok) return response.bodyBytes;
  if (allowMissing && response.statusCode == HttpStatus.notFound) return null;
  throw HttpException('HTTP ${response.statusCode}', uri: uri);
}
