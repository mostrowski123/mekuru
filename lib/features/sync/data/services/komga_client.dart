import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mekuru/core/services/http_transport.dart';

import '../models/remote_models.dart';
import 'http_server_client.dart';
import 'server_client.dart';

/// Client for a Komga server (REST API v1).
///
/// [secret] is either an API key (sent as `X-API-Key`) or `user:password`
/// (sent as HTTP Basic) — Komga API keys never contain a colon, so the
/// presence of one selects Basic auth.
class KomgaClient extends HttpServerClient {
  final String Function() getSecret;

  static const _pageSize = 200;

  KomgaClient({
    required super.baseUrl,
    required this.getSecret,
    super.httpClient,
    super.requestTimeout,
  }) : super(serverName: 'Komga');

  Map<String, String> get _authHeaders {
    final secret = getSecret();
    if (secret.contains(':')) {
      return {'Authorization': 'Basic ${base64Encode(utf8.encode(secret))}'};
    }
    return {'X-API-Key': secret};
  }

  @override
  Future<http.Response> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async => ensureSuccess(
    await sendRaw(
      method,
      path,
      headers: {..._authHeaders, ...?headers},
      body: body,
    ),
    method,
    path,
  );

  /// Komga serves a book's progression and position list as Readium media
  /// types and answers 406 to the `Accept: application/json` every other
  /// request sends.
  static const _readiumAccept = {'Accept': '*/*'};

  /// The start of each `message` Komga refuses a progress write with, and
  /// the code reported for it. The message itself can name a file in the
  /// book, so it stays here.
  static const _refusals = {
    'Resource does not exist in book': 'resource_not_in_book',
    'Invalid progression': 'invalid_progression',
    'location.progression is required': 'progression_required',
    'Progression is older than existing': 'older_than_existing',
    'Epub extension not found': 'epub_not_analyzed',
    'Media has no profile': 'media_not_analyzed',
    'Page argument': 'page_out_of_range',
    'epub book is not Divina compatible': 'epub_not_page_based',
  };

  @override
  String? refusalReason(http.Response response) {
    try {
      if (decodeJsonBody(response) case {'message': final String message}) {
        for (final MapEntry(:key, :value) in _refusals.entries) {
          if (message.startsWith(key)) return value;
        }
      }
    } on FormatException {
      // Not JSON: a proxy's error page.
    }
    return null;
  }

  @override
  Future<void> testConnection() async {
    await getJson('/api/v1/libraries');
  }

  @override
  Future<List<RemoteLibrary>> listLibraries() async {
    final json = await getJson('/api/v1/libraries') as List;
    return [
      for (final lib in json.whereType<Map<String, dynamic>>())
        RemoteLibrary(id: lib['id'] as String, name: lib['name'] as String),
    ];
  }

  @override
  Future<List<RemoteSeries>> listSeries(
    String libraryId, {
    String? search,
  }) async {
    final result = <RemoteSeries>[];
    for (var page = 0; ; page++) {
      final query = Uri(
        queryParameters: {
          'library_id': libraryId,
          'page': '$page',
          'size': '$_pageSize',
          if (search != null && search.isNotEmpty) 'search': search,
        },
      ).query;
      final json = await getJson('/api/v1/series?$query');
      final content = (json as Map<String, dynamic>)['content'] as List;
      for (final series in content.whereType<Map<String, dynamic>>()) {
        final metadata = series['metadata'] as Map<String, dynamic>?;
        result.add(
          RemoteSeries(
            id: series['id'] as String,
            libraryId: libraryId,
            title: (metadata?['title'] as String?) ?? series['name'] as String,
            bookCount: (series['booksCount'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      if (json['last'] == true || content.isEmpty) break;
    }
    return result;
  }

  @override
  Future<List<RemoteBook>> listBooks(RemoteSeries series) async {
    final result = <RemoteBook>[];
    for (var page = 0; ; page++) {
      final json = await getJson(
        '/api/v1/series/${series.id}/books?page=$page&size=$_pageSize',
      );
      final content = (json as Map<String, dynamic>)['content'] as List;
      for (final book in content.whereType<Map<String, dynamic>>()) {
        final media = book['media'] as Map<String, dynamic>?;
        final profile = media?['mediaProfile'] as String?;
        final metadata = book['metadata'] as Map<String, dynamic>?;
        final isEpub = profile == 'EPUB';
        result.add(
          RemoteBook(
            ids: {
              'bookId': book['id'] as String,
              'seriesId': series.id,
              if (isEpub) 'epub': 'true',
            },
            title: (metadata?['title'] as String?) ?? book['name'] as String,
            seriesTitle: series.title,
            format: switch (profile) {
              'EPUB' => RemoteBookFormat.epub,
              'PDF' => RemoteBookFormat.pdf,
              _ => RemoteBookFormat.imageArchive,
            },
            pageCount: (media?['pagesCount'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      if (json['last'] == true || content.isEmpty) break;
    }
    return result;
  }

  @override
  Future<({String url, Map<String, String> headers})> downloadRequest(
    RemoteBook book,
  ) async => (
    url: '$baseUrl/api/v1/books/${book.ids['bookId']}/file',
    headers: _authHeaders,
  );

  @override
  Future<List<int>?> fetchSeriesCover(RemoteSeries series) async {
    try {
      final response = await send(
        'GET',
        '/api/v1/series/${series.id}/thumbnail',
      );
      return response.bodyBytes;
    } on SyncException {
      return null;
    }
  }

  @override
  Future<RemoteProgress?> pullProgress(Map<String, String> ids) async {
    final bookId = ids['bookId'];
    if (bookId == null) return null;
    final book = await getJson('/api/v1/books/$bookId') as Map<String, dynamic>;
    final readProgress = book['readProgress'] as Map<String, dynamic>?;

    String? href;
    double? progression;
    double? totalProgression;
    DateTime? locatorModified;
    if (ids['epub'] == 'true') {
      // The Readium progression record carries the precise EPUB position.
      try {
        final r2 = decodeJsonBody(
          await send(
            'GET',
            '/api/v1/books/$bookId/progression',
            headers: _readiumAccept,
          ),
        );
        if (r2 is Map<String, dynamic>) {
          final locator = r2['locator'] as Map<String, dynamic>?;
          final locations = locator?['locations'] as Map<String, dynamic>?;
          href = locator?['href'] as String?;
          progression = (locations?['progression'] as num?)?.toDouble();
          totalProgression = (locations?['totalProgression'] as num?)
              ?.toDouble();
          locatorModified = DateTime.tryParse(r2['modified'] as String? ?? '');
        }
      } on SyncException {
        // An older Komga without the record: the page-based read progress
        // below still applies.
      } on FormatException {
        // No record yet: a 204 with no body.
      }
    }

    if (readProgress == null && href == null) return null;

    final serverPage = (readProgress?['page'] as num?)?.toInt();
    // Without a Readium record, the page-based read progress still yields a
    // whole-book fraction through the server's page count.
    final pagesCount =
        ((book['media'] as Map<String, dynamic>?)?['pagesCount'] as num?)
            ?.toInt() ??
        0;
    if (totalProgression == null && serverPage != null && pagesCount > 0) {
      totalProgression = (serverPage / pagesCount).clamp(0.0, 1.0);
    }
    return RemoteProgress(
      // Komga pages are 1-based; unified model is a 0-based index.
      page: serverPage != null && serverPage > 0 ? serverPage - 1 : null,
      completed: readProgress?['completed'] == true,
      href: href,
      progression: progression,
      totalProgression: totalProgression,
      lastModified:
          locatorModified ??
          DateTime.tryParse(readProgress?['lastModified'] as String? ?? ''),
    );
  }

  /// Komga's position list of the EPUB last pushed to. One book, because a
  /// list has an entry per KB of text and Sync Now pushes every linked book.
  ({String bookId, List<Map<String, dynamic>> list})? _positions;

  /// The book's position list; empty when the server gives none, and the
  /// push then sends the reader's own locator.
  Future<List<Map<String, dynamic>>> _positionsOf(String bookId) async {
    if (_positions case (
      bookId: final known,
      :final list,
    ) when known == bookId) {
      return list;
    }
    var list = const <Map<String, dynamic>>[];
    try {
      final body = decodeJsonBody(
        await send(
          'GET',
          '/api/v1/books/$bookId/positions',
          headers: _readiumAccept,
        ),
      );
      if (body case {'positions': final List positions}) {
        list = positions.whereType<Map<String, dynamic>>().toList();
      }
    } on SyncException catch (e) {
      if (e.isUnreachable) rethrow;
    } on FormatException {
      // Not JSON: a proxy's page.
    }
    _positions = (bookId: bookId, list: list);
    return list;
  }

  @override
  Future<void> pushProgress(
    Map<String, String> ids,
    RemoteProgress progress,
  ) async {
    final bookId = ids['bookId'];
    if (bookId == null) return;
    if (ids['epub'] == 'true' && progress.href != null) {
      final locator =
          komgaPositionFor(await _positionsOf(bookId), progress) ??
          {
            'href': progress.href,
            'type': 'application/xhtml+xml',
            'locations': {
              if (progress.progression != null)
                'progression': progress.progression,
              if (progress.totalProgression != null)
                'totalProgression': progress.totalProgression,
            },
          };
      try {
        await send(
          'PUT',
          '/api/v1/books/$bookId/progression',
          body: {
            'modified': DateTime.now().toUtc().toIso8601String(),
            'device': {'id': 'mekuru', 'name': 'Mekuru'},
            'locator': locator,
          },
        );
      } on SyncException catch (e) {
        // The book may have changed on the server since its list was read,
        // or the list could not be read then.
        if (e.statusCode == 400) _positions = null;
        rethrow;
      }
      if (progress.completed) {
        await send(
          'PATCH',
          '/api/v1/books/$bookId/read-progress',
          body: {'completed': true},
        );
      }
      return;
    }
    if (progress.page == null && !progress.completed) return;
    await send(
      'PATCH',
      '/api/v1/books/$bookId/read-progress',
      body: {
        // Unified 0-based index back to Komga's 1-based page.
        if (progress.page != null) 'page': progress.page! + 1,
        'completed': progress.completed,
      },
    );
  }
}

/// The entry of Komga's position list (`GET …/positions`) for the reader's
/// place, or null when the list gives nothing to go by.
///
/// Komga refuses a pushed locator unless its href is one of the book's
/// zip-root paths and its progression is one of these positions or lies
/// between two of them. The reader's href is relative to the package file
/// and its progression can pass a chapter's last position, so the push sends
/// Komga's own entry: the one at or before the reader's place in the chapter
/// or, when the server's copy has no such chapter (another edition of the
/// book), the one at or before the same fraction of the whole book.
Map<String, dynamic>? komgaPositionFor(
  List<Map<String, dynamic>> positions,
  RemoteProgress progress,
) {
  if (positions.isEmpty) return null;
  final href = _plainHref(progress.href ?? '');
  final chapter = [
    for (final p in positions)
      if (p['href'] case final String h when h == href || h.endsWith('/$href'))
        p,
  ];
  // One file name in two folders matches both chapters, so neither.
  if (chapter.isNotEmpty &&
      chapter.every((p) => p['href'] == chapter.first['href'])) {
    return _atOrBefore(chapter, 'progression', progress.progression ?? 0);
  }
  final total = progress.totalProgression;
  return total == null
      ? null
      : _atOrBefore(positions, 'totalProgression', total);
}

/// The last of [positions], which are in reading order, whose [location] is
/// not past [target]; the first when all are.
Map<String, dynamic> _atOrBefore(
  List<Map<String, dynamic>> positions,
  String location,
  double target,
) => positions.lastWhere(
  (p) => ((p['locations'] as Map?)?[location] as num? ?? 0) <= target,
  orElse: () => positions.first,
);

/// [href] as Komga lists paths: without a fragment, percent-decoded.
String _plainHref(String href) {
  final path = href.split('#').first;
  try {
    return Uri.decodeFull(path);
  } catch (_) {
    // A file name with a literal '%'.
    return path;
  }
}
