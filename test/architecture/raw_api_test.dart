import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A raw API that has a helper in this repo, and the files under [dir] that
/// use it today. A file that gains a use fails with the helper to call
/// instead. A file that loses one fails until its number here is lowered, so
/// the numbers only go down.
class _Row {
  const _Row(
    this.what,
    this.uses,
    this.use, {
    this.counts = const {},
    this.allowed = const {},
    this.within = '',
    this.dir = 'lib',
  });

  final String what;

  /// Only files in [dir] whose path contains this are scanned.
  final String within;

  /// The folder the row scans: `lib` or `test`.
  final String dir;

  /// The line of each use in a file's source, comment lines blanked.
  final List<int> Function(String source) uses;

  /// What to call instead, and where it lives.
  final String use;

  /// Known violations: uses per file today.
  final Map<String, int> counts;

  /// Uses read and judged legitimate: uses per file today, and why.
  final Map<String, (int, String)> allowed;
}

final _rows = [
  // Counted as found at e3e39d7d, not judged use by use.
  _Row(
    'Platform.isIOS or Platform.isAndroid',
    _matching(r'\bPlatform\.is(IOS|Android)\b'),
    'defaultTargetPlatform, which tests switch with '
        'debugDefaultTargetPlatformOverride (package:flutter/foundation.dart)',
    counts: {
      'lib/core/platform/ios_storage.dart': 1,
      'lib/core/services/sentry_setup.dart': 2,
      'lib/features/backup/data/services/prepare_staged_restore.dart': 1,
      'lib/features/library/data/repositories/book_repository.dart': 1,
      'lib/features/library/presentation/screens/library_screen.dart': 5,
      'lib/features/sync/data/services/server_client.dart': 2,
      'lib/features/sync/presentation/providers/sync_providers.dart': 2,
      'lib/shared/widgets/adaptive_body.dart': 1,
    },
  ),
  _Row(
    'A platform check that picks an l10n key or its …Ios sibling',
    _matching(
      r'\b(TargetPlatform\.(iOS|android)|Platform\.is(IOS|Android))\b'
      r'[^;{}]{0,160}?\.\w+Ios\b',
    ),
    'a switch on wording, with both keys '
        '(lib/core/platform/capabilities.dart)',
  ),
  _Row(
    'ZipDecoder().decodeBytes or readBytes() on a zip entry',
    _matching(r'\bZipDecoder\(\)\s*\.decodeBytes\(|\.readBytes\(\)'),
    'ZipDecoder().decodeStream(InputFileStream(path)) and read each entry '
        'once, with .content then clear(), as CbzParser._extractZip does '
        '(lib/features/manga/data/services/cbz_parser.dart)',
  ),
  _Row(
    'Uri.decodeFull, decodeComponent or decodeQueryComponent',
    _matching(r'\bUri\.decode(Full|Component|QueryComponent)\('),
    'resolveEpubHref for an EPUB href '
        '(lib/features/library/data/services/epub_parser.dart), decodeHref '
        'for any other link (lib/core/utils/xhtml.dart): a link that does '
        'not decode keeps its literal text instead of throwing',
    allowed: {'lib/core/utils/xhtml.dart': (1, 'decodeHref itself')},
  ),
  // Counted as found at e3e39d7d, not judged use by use.
  _Row(
    'writeAsString or writeAsBytes',
    _matching(r'\.writeAs(String|Bytes)(Sync)?\('),
    'writeStringAtomic or writeBytesAtomic (lib/core/utils/atomic_file.dart)',
    counts: {
      'lib/features/backup/data/services/backup_file_manager.dart': 1,
      'lib/features/backup/data/services/dart_full_backup_job.dart': 1,
      'lib/features/backup/data/services/full_backup_service.dart': 2,
      'lib/features/backup/data/services/prepare_staged_restore.dart': 1,
      'lib/features/free_books/presentation/providers/free_books_providers.dart':
          1,
      'lib/features/library/data/repositories/book_repository.dart': 1,
      'lib/features/library/data/services/epub_parser.dart': 1,
      'lib/features/manga/data/services/cbz_parser.dart': 2,
      'lib/features/manga/data/services/pdf_pages.dart': 1,
      'lib/features/reader/data/services/mecab_service.dart': 1,
      'lib/features/settings/data/services/enhanced_furigana_dict_download_service.dart':
          1,
      'lib/features/settings/data/services/kanjivg_download_service.dart': 2,
      'lib/features/sync/data/services/server_download_work.dart': 2,
      'lib/features/vocabulary/data/repositories/vocabulary_repository.dart': 1,
      // Moved from model_download.dart: a model's INSTALLED marker.
      'lib/shared/downloads/download.dart': 1,
    },
    allowed: {
      'lib/core/utils/atomic_file.dart': (1, 'the atomic write itself'),
    },
  ),
  _Row(
    'scaffoldMessengerKey',
    _matching(r'\bscaffoldMessengerKey\b'),
    "ScaffoldMessenger.of(context), which in a sheet is the sheet's own, as "
        'LookupSheet sets up '
        '(lib/features/reader/presentation/widgets/lookup_sheet.dart), or '
        'announce() for work that outlives its screen (lib/main.dart)',
    allowed: {
      'lib/app.dart': (5, 'hands the key to MaterialApp'),
      'lib/main.dart': (4, 'declares the key, appL10n() and announce()'),
    },
  ),
  _Row(
    'An English string literal in Text, tooltip, labelText or hintText',
    _matching(
      r'''(Text\(|tooltip:|labelText:|hintText:)\s*['"][A-Z][a-z]+[ a-zA-Z]''',
    ),
    'an l10n key: add it to lib/l10n/app_en.arb and read it with '
        'context.l10n (lib/l10n/l10n.dart)',
    allowed: {
      'lib/features/dictionary/presentation/screens/dictionary_manager_screen.dart':
          (2, 'the lookup benchmark, shown only in debug builds'),
      'lib/features/manga/presentation/screens/pro_upgrade_screen.dart': (
        3,
        "the testers' sandbox refund button and its message, and the name "
            'Comic Text Detector',
      ),
      'lib/features/settings/presentation/screens/attributions_screen.dart': (
        1,
        "epub.js's licence, which stays verbatim",
      ),
      'lib/features/settings/presentation/widgets/ocr_attributions.dart': (
        1,
        'the name Comic Text Detector',
      ),
      'lib/features/sync/presentation/screens/server_settings_screen.dart': (
        2,
        'the names Komga and Kavita',
      ),
    },
  ),
  _Row(
    "A String error or message in a provider's state",
    _matching(r'\bfinal String\?\s+\w*([eE]rror|[mM]essage)\b'),
    'what happened (the exception, or an enum or record such as '
        'TileOutcome in lib/shared/downloads/download.dart), worded by the '
        "widget with its own context's l10n, as DownloadOutcomeText does "
        '(lib/shared/widgets/download_status.dart)',
    within: '/providers/',
    counts: {
      // A native job's error code, or an exception's text.
      'lib/features/manga/presentation/providers/local_ocr_providers.dart': 1,
    },
  ),
  // The uses left in files other work held when this row came in.
  _Row(
    "An exception's own text handed to the user: details: '\$e', "
        "details: e.toString() or Text('\$error')",
    _matching(
      r"\bdetails:\s*('\$\{?\w|\w+(\.error)?\.toString\(\))|"
      r"\bText\(\s*'\$\{?(e|err|error)\b",
    ),
    'words for what did not happen and what to do, as dictionaryDownloadError '
        'does (lib/shared/widgets/download_status.dart), or LoadFailedText for '
        'a list that cannot load (lib/shared/widgets/load_failed_text.dart); '
        'the error itself goes to logFailure '
        '(lib/core/services/usage_telemetry.dart)',
    counts: {
      // The message leaves {details} out in every language.
      'lib/features/manga/presentation/screens/manga_reader_screen.dart': 1,
      // Signed-in cloud OCR only; no test reaches it yet.
      'lib/features/manga/presentation/screens/pro_upgrade_screen.dart': 1,
      'lib/features/settings/presentation/widgets/ocr_server_url_dialog.dart':
          1,
    },
  ),
  _Row(
    'NetworkConsent.mobileData, a download allowed mobile data unasked',
    _matching(r'\bNetworkConsent\.mobileData\b'),
    'askNetwork(), the one mobile-data question, for the consent '
        '(lib/shared/widgets/mobile_data_dialog.dart)',
    allowed: {
      'lib/shared/widgets/mobile_data_dialog.dart': (1, 'askNetwork itself'),
    },
  ),
  _Row(
    'A raw HttpClient, IOClient, or package:http client or request',
    _matching(
      r'\bHttpClient(\(|\.new\b)|\bIOClient\(|\bhttp\.(Client|Request|'
      r'MultipartRequest|StreamedRequest|get|post|put|patch|delete|head|'
      r'read|readBytes)\(',
    ),
    'runDownload for a download (lib/shared/downloads/download.dart), or '
        "sendWithTimeout on an API class's own client "
        '(lib/core/services/http_transport.dart)',
    counts: {
      // Free books: to move onto runDownload, which owns their rules then.
      'lib/features/free_books/data/services/aozora_download.dart': 1,
      'lib/features/free_books/presentation/providers/free_books_providers.dart':
          2,
    },
    allowed: {
      'lib/core/services/download_to_file.dart': (
        1,
        "downloadToFile, the transfer of a part runDownload doesn't resume",
      ),
      'lib/core/services/server_http_client.dart': (
        3,
        'the transport of a server the user added (Komga, Kavita, the OCR '
            'server), with the self-signed certificate they allowed',
      ),
      'lib/features/ankidroid/data/services/anki_connect_service.dart': (
        1,
        "AnkiConnect, an API on the user's computer",
      ),
      'lib/features/manga/data/services/manga_ocr_client.dart': (
        2,
        'the OCR server API',
      ),
      'lib/features/manga/data/services/model_download_job.dart': (
        1,
        "a background model download's client, run by runWorkerDownload",
      ),
      'lib/features/manga/data/services/ocr_billing_client.dart': (
        2,
        'the billing API',
      ),
      'lib/features/settings/data/services/ocr_server_health_client.dart': (
        2,
        "the OCR server's health check",
      ),
      'lib/features/sync/data/services/http_server_client.dart': (
        2,
        'the Komga and Kavita APIs',
      ),
      'lib/features/wanikani/data/services/wanikani_api_client.dart': (
        2,
        'the WaniKani API',
      ),
      'lib/shared/downloads/download.dart': (
        1,
        'runDownload itself: a client per transfer, which a stop or a Wi-Fi '
            'drop closes',
      ),
    },
  ),
  _Row(
    'FilePicker, or a file dialog on the mekuru/android_saf or '
        'mekuru/ios_files channel',
    _matching(
      r"\bFilePicker\.|'(pickDirectory|pickDocument|saveDocument|pickFolder|"
      r"pickZip|exportFile)'",
    ),
    'pickFiles, pickAndroidFolder, pickAndroidZip, pickIosFolder, pickIosZip '
        'or saveFile (lib/core/platform/file_pick.dart), which handle every '
        'failure a file dialog is known to have',
    allowed: {
      'lib/core/platform/file_pick.dart': (8, 'the file dialogs themselves'),
    },
  ),
  _Row(
    'Image.file or FileImage',
    _matching(r'\bImage\.file\(|\bFileImage\('),
    'fileImage(), which also shows AVIF on iOS and Android 7-11 '
        '(lib/core/platform/image_convert.dart)',
    allowed: {
      'lib/core/platform/image_convert.dart': (1, 'fileImage() itself'),
    },
  ),
  // Counted as found at e3e39d7d, not judged use by use.
  _Row(
    'ref.read, ref.watch, ref.listen, ref.refresh or ref.invalidate after an '
        'await with no mounted check between',
    _refAfterAwait,
    'a value read before the first await, or a mounted check after it '
        '(if (!mounted) return;)',
    counts: {
      'lib/features/backup/presentation/providers/backup_providers.dart': 27,
      'lib/features/backup/presentation/providers/full_backup_job_provider.dart':
          1,
      'lib/features/backup/presentation/screens/backup_settings_screen.dart': 3,
      'lib/features/dictionary/presentation/providers/dictionary_catalog_providers.dart':
          2,
      'lib/features/free_books/presentation/providers/free_books_providers.dart':
          1,
      'lib/features/library/presentation/providers/library_providers.dart': 1,
      'lib/features/library/presentation/widgets/epub_manga_convert_action.dart':
          1,
      'lib/features/library/presentation/widgets/furigana_export_action.dart':
          2,
      'lib/features/library/presentation/widgets/manga_cbz_export_action.dart':
          1,
      'lib/features/manga/presentation/providers/local_ocr_providers.dart': 2,
      'lib/features/manga/presentation/screens/manga_reader_screen.dart': 4,
      'lib/features/manga/presentation/widgets/local_ocr_page_overlay.dart': 1,
      'lib/features/manga/presentation/widgets/ocr_action_sheet.dart': 7,
      'lib/features/reader/presentation/screens/reader_screen.dart': 1,
      'lib/features/settings/presentation/providers/app_settings_providers.dart':
          1,
      'lib/features/settings/presentation/providers/enhanced_furigana_dict_providers.dart':
          2,
      'lib/features/settings/presentation/screens/settings_screen.dart': 4,
      'lib/features/sync/presentation/screens/server_settings_screen.dart': 1,
      'lib/features/wanikani/presentation/providers/wanikani_providers.dart': 3,
      'lib/features/wanikani/presentation/screens/wanikani_settings_screen.dart':
          2,
    },
  ),
  _Row(
    'A test that builds its own AppDatabase',
    _matching(r'\bAppDatabase\('),
    'createTestDatabase(), an in-memory database '
        '(test/shared/test_database.dart)',
    dir: 'test',
    allowed: {
      'test/shared/test_database.dart': (1, 'createTestDatabase() itself'),
      'test/database_migration_test.dart': (
        31,
        'migrates a database file and reopens it',
      ),
      'test/database_busy_timeout_test.dart': (
        1,
        "the default constructor's on-disk connection",
      ),
      'test/features/backup/full_backup_plan_test.dart': (
        1,
        'writes the snapshot file the plan reads',
      ),
      'test/features/backup/prepare_staged_restore_test.dart': (
        1,
        'writes the staged database file the restore reads',
      ),
      'test/features/dictionary/dictionary_import_full_disk_test.dart': (
        1,
        'a database file capped in size, on a background isolate, to fill it',
      ),
    },
  ),
];

/// The scan for the pattern rows: the line of every match.
List<int> Function(String) _matching(String pattern) {
  final regex = RegExp(pattern);
  return (source) => [
    for (final m in regex.allMatches(source)) _lineOf(source, m.start),
  ];
}

final _refUse = RegExp(r'\bref\.(read|watch|listen|refresh|invalidate)\(');
final _asyncBody = RegExp(r'\basync\*?\s*\{');
final _await = RegExp(r'\bawait\b');

/// Lines where `ref` is used after an await in the same async body, with no
/// line naming `mounted` since that await.
// shortcut: braces inside strings are counted too, and a nested closure's own
// ref (a Consumer builder's) counts as the body's. An AST visitor would fix
// both.
List<int> _refAfterAwait(String source) {
  final found = <int>{};
  for (final m in _asyncBody.allMatches(source)) {
    var depth = 1;
    var end = m.end;
    for (; end < source.length && depth > 0; end++) {
      final c = source.codeUnitAt(end);
      if (c == 0x7B) depth++;
      if (c == 0x7D) depth--;
    }
    final first = _lineOf(source, m.end);
    var awaited = false;
    var guarded = false;
    final lines = source.substring(m.end, end).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('mounted')) guarded = true;
      if (awaited && !guarded && _refUse.hasMatch(lines[i])) {
        found.add(first + i);
      }
      if (_await.hasMatch(lines[i])) {
        awaited = true;
        guarded = false;
      }
    }
  }
  return found.toList()..sort();
}

int _lineOf(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

void main() {
  // Comment lines are blanked, not dropped, so line numbers stay true.
  final sources = <String, String>{
    for (final dir in ['lib', 'test'])
      for (final f in Directory(dir).listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart'))
          if (f.path.replaceAll(r'\', '/') case final path
              when !path.startsWith('lib/l10n/generated/'))
            path: [
              for (final line in f.readAsLinesSync())
                line.trimLeft().startsWith('//') ? '' : line,
            ].join('\n'),
  };

  test('scans the hand-written Dart files under lib and test', () {
    expect(sources, isNotEmpty);
  });

  for (final row in _rows) {
    test(row.what, () {
      final found = <String, List<int>>{};
      sources.forEach((path, source) {
        if (!path.startsWith('${row.dir}/') || !path.contains(row.within)) {
          return;
        }
        final lines = row.uses(source);
        if (lines.isNotEmpty) found[path] = lines;
      });
      final problems = <String>[];
      for (final path in {
        ...found.keys,
        ...row.counts.keys,
        ...row.allowed.keys,
      }) {
        final lines = found[path] ?? const [];
        final recorded = row.counts[path] ?? row.allowed[path]?.$1 ?? 0;
        if (lines.length > recorded) {
          problems.add(
            '${row.what} in $path. Use ${row.use}. Found ${lines.length} '
            '(lines ${lines.toSet().join(', ')}), recorded $recorded.',
          );
        } else if (lines.length < recorded) {
          problems.add(
            '${row.what} in $path: found ${lines.length}, recorded '
            '$recorded. Lower the recorded count in '
            'test/architecture/raw_api_test.dart to ${lines.length}.',
          );
        }
      }
      problems.sort();
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
