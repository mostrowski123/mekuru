import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mekuru/core/services/download_to_file.dart';

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
  }) async => ensureSuccess(
    await sendRaw(method, path, headers: _authHeaders, body: body),
    method,
    path,
  );

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
        // Mekuru has no PDF reader; don't offer what can't be imported.
        if (profile == 'PDF') continue;
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
            format: isEpub
                ? RemoteBookFormat.epub
                : RemoteBookFormat.imageArchive,
            pageCount: (media?['pagesCount'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      if (json['last'] == true || content.isEmpty) break;
    }
    return result;
  }

  @override
  Future<void> downloadBook(
    RemoteBook book,
    String destPath, {
    void Function(double progress)? onProgress,
  }) {
    return downloadToFile(
      '$baseUrl/api/v1/books/${book.ids['bookId']}/file',
      destPath,
      headers: _authHeaders,
      onProgress: onProgress,
    );
  }

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
        final r2 = await getJson('/api/v1/books/$bookId/progression');
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
        // No progression record yet (or an older Komga) — the page-based
        // read progress below still applies.
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

  @override
  Future<void> pushProgress(
    Map<String, String> ids,
    RemoteProgress progress,
  ) async {
    final bookId = ids['bookId'];
    if (bookId == null) return;
    if (ids['epub'] == 'true' && progress.href != null) {
      await send(
        'PUT',
        '/api/v1/books/$bookId/progression',
        body: {
          'modified': DateTime.now().toUtc().toIso8601String(),
          'device': {'id': 'mekuru', 'name': 'Mekuru'},
          'locator': {
            'href': progress.href,
            'type': 'application/xhtml+xml',
            'locations': {
              if (progress.progression != null)
                'progression': progress.progression,
              if (progress.totalProgression != null)
                'totalProgression': progress.totalProgression,
            },
          },
        },
      );
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
