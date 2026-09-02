import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mekuru/core/services/download_to_file.dart';

import '../models/remote_models.dart';
import 'http_server_client.dart';
import 'server_client.dart';

/// Client for a Kavita server.
///
/// [getSecret] returns the user's Kavita API key; it is exchanged for a JWT
/// via `POST /api/Plugin/authenticate` and re-exchanged once on any 401.
///
/// Kavita has no Readium locator API: EPUB progress maps through the
/// chapter's server-side page count (`pageNum ≈ totalProgression * pages`),
/// so EPUB sync against Kavita is chapter-granular by design.
class KavitaClient extends HttpServerClient {
  final String Function() getSecret;

  static const _pluginName = 'Mekuru';
  static const _pageSize = 100;

  // Kavita SeriesFilterField/FilterComparison/FilterCombination enum values.
  static const _fieldLibraries = 19;
  static const _comparisonContains = 5;
  static const _combinationAnd = 1;

  // Kavita MangaFormat enum values.
  static const _formatEpub = 3;
  static const _formatPdf = 4;

  String? _jwt;

  KavitaClient({
    required super.baseUrl,
    required this.getSecret,
    super.httpClient,
    super.requestTimeout,
  }) : super(serverName: 'Kavita');

  static Map<String, String> _bearer(String token) => {
    'Authorization': 'Bearer $token',
  };

  Future<String> _authenticate() async {
    final key = Uri.encodeQueryComponent(getSecret());
    final response = await sendRaw(
      'POST',
      '/api/Plugin/authenticate?apiKey=$key&pluginName=$_pluginName',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncException(response.statusCode, 'Kavita rejected the API key');
    }
    final token =
        (jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>)['token']
            as String?;
    if (token == null || token.isEmpty) {
      throw SyncException(0, 'Kavita returned no token');
    }
    _jwt = token;
    return token;
  }

  /// Send an authenticated request, re-authenticating once on 401.
  @override
  Future<http.Response> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    var token = _jwt ?? await _authenticate();
    var response = await sendRaw(
      method,
      path,
      headers: _bearer(token),
      body: body,
    );
    if (response.statusCode == 401) {
      token = await _authenticate();
      response = await sendRaw(
        method,
        path,
        headers: _bearer(token),
        body: body,
      );
    }
    return ensureSuccess(response, method, path);
  }

  @override
  Future<void> testConnection() async {
    await _authenticate();
    await getJson('/api/Library/libraries');
  }

  @override
  Future<List<RemoteLibrary>> listLibraries() async {
    final json = await getJson('/api/Library/libraries') as List;
    return [
      for (final lib in json.whereType<Map<String, dynamic>>())
        RemoteLibrary(id: '${lib['id']}', name: lib['name'] as String),
    ];
  }

  @override
  Future<List<RemoteSeries>> listSeries(
    String libraryId, {
    String? search,
  }) async {
    if (search != null && search.isNotEmpty) {
      final json =
          await getJson(
                '/api/Search/search?queryString='
                '${Uri.encodeQueryComponent(search)}',
              )
              as Map<String, dynamic>;
      final series = json['series'] as List? ?? const [];
      return [
        for (final s in series.whereType<Map<String, dynamic>>())
          if ('${s['libraryId']}' == libraryId)
            RemoteSeries(
              id: '${s['seriesId'] ?? s['id']}',
              libraryId: libraryId,
              title: s['name'] as String? ?? '',
              bookCount: 0,
            ),
      ];
    }

    final result = <RemoteSeries>[];
    for (var page = 1; ; page++) {
      final response = await send(
        'POST',
        '/api/Series/v2?PageNumber=$page&PageSize=$_pageSize',
        body: {
          'statements': [
            {
              'comparison': _comparisonContains,
              'field': _fieldLibraries,
              'value': libraryId,
            },
          ],
          'combination': _combinationAnd,
          'limitTo': 0,
        },
      );
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      for (final s in json.whereType<Map<String, dynamic>>()) {
        result.add(
          RemoteSeries(
            id: '${s['id']}',
            libraryId: libraryId,
            title: s['name'] as String? ?? '',
            bookCount: 0,
          ),
        );
      }
      if (json.length < _pageSize) break;
    }
    return result;
  }

  @override
  Future<List<RemoteBook>> listBooks(RemoteSeries series) async {
    final volumes =
        await getJson('/api/Series/volumes?seriesId=${series.id}') as List;
    final result = <RemoteBook>[];
    for (final volume in volumes.whereType<Map<String, dynamic>>()) {
      final chapters = volume['chapters'] as List? ?? const [];
      for (final chapter in chapters.whereType<Map<String, dynamic>>()) {
        final format = (chapter['format'] as num?)?.toInt();
        // Mekuru has no PDF reader; don't offer what can't be imported.
        if (format == _formatPdf) continue;
        final pages = (chapter['pages'] as num?)?.toInt() ?? 0;
        final chapterTitle = chapter['titleName'] as String?;
        final volumeName = volume['name'] as String?;
        result.add(
          RemoteBook(
            ids: {
              'chapterId': '${chapter['id']}',
              'volumeId': '${volume['id']}',
              'seriesId': series.id,
              'libraryId': series.libraryId,
              // Carried so progress calls can convert to/from pageNum
              // without refetching the chapter.
              'pages': '$pages',
              if (format == _formatEpub) 'epub': 'true',
            },
            title: (chapterTitle != null && chapterTitle.isNotEmpty)
                ? chapterTitle
                : (volumeName ?? series.title),
            seriesTitle: series.title,
            format: format == _formatEpub
                ? RemoteBookFormat.epub
                : RemoteBookFormat.imageArchive,
            pageCount: pages,
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<void> downloadBook(
    RemoteBook book,
    String destPath, {
    void Function(double progress)? onProgress,
  }) async {
    final token = _jwt ?? await _authenticate();
    return downloadToFile(
      '$baseUrl/api/Download/chapter?chapterId=${book.ids['chapterId']}',
      destPath,
      headers: _bearer(token),
      onProgress: onProgress,
    );
  }

  @override
  Future<List<int>?> fetchSeriesCover(RemoteSeries series) async {
    try {
      final response = await send(
        'GET',
        '/api/Image/series-cover?seriesId=${series.id}',
      );
      return response.bodyBytes;
    } on SyncException {
      return null;
    }
  }

  @override
  Future<RemoteProgress?> pullProgress(Map<String, String> ids) async {
    final chapterId = ids['chapterId'];
    if (chapterId == null) return null;
    final json = await getJson('/api/Reader/get-progress?chapterId=$chapterId');
    if (json is! Map<String, dynamic>) return null;
    final pageNum = (json['pageNum'] as num?)?.toInt();
    if (pageNum == null || pageNum <= 0) return null;
    final pages = int.tryParse(ids['pages'] ?? '') ?? 0;
    return RemoteProgress(
      page: pageNum,
      completed: pages > 0 && pageNum >= pages,
      totalProgression: pages > 0 ? (pageNum / pages).clamp(0.0, 1.0) : null,
      lastModified: _parseUtc(json['lastModifiedUtc'] as String?),
    );
  }

  /// Kavita (ASP.NET + EF Core) can serialize a UTC timestamp without its
  /// `Z`, which Dart would read as local time.
  static DateTime? _parseUtc(String? iso) {
    if (iso == null) return null;
    final zoned = RegExp(r'([zZ]|[+-]\d{2}:?\d{2})$').hasMatch(iso);
    return DateTime.tryParse(zoned ? iso : '${iso}Z');
  }

  @override
  Future<void> pushProgress(
    Map<String, String> ids,
    RemoteProgress progress,
  ) async {
    final chapterId = int.tryParse(ids['chapterId'] ?? '');
    if (chapterId == null) return;
    final pages = int.tryParse(ids['pages'] ?? '') ?? 0;
    int? pageNum = progress.page;
    if (pageNum == null && progress.totalProgression != null && pages > 0) {
      // EPUB approximation: Kavita has no locator API, so position maps
      // through its server-side page count.
      pageNum = (progress.totalProgression! * pages).floor();
    }
    if (progress.completed && pages > 0) pageNum = pages;
    if (pageNum == null) return;
    await send(
      'POST',
      '/api/Reader/progress',
      body: {
        'volumeId': int.tryParse(ids['volumeId'] ?? '') ?? 0,
        'chapterId': chapterId,
        'seriesId': int.tryParse(ids['seriesId'] ?? '') ?? 0,
        'libraryId': int.tryParse(ids['libraryId'] ?? '') ?? 0,
        'pageNum': pageNum.clamp(0, pages > 0 ? pages : pageNum),
        'bookScrollId': null,
        'lastModifiedUtc': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}
