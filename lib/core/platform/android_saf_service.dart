import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Persisted SAF tree access info for a picked document on Android.
class AndroidSafTreeAccess {
  final String treeUri;
  final String? treeDocumentId;
  final String selectedFileUri;
  final String? selectedFileDocumentId;
  final String? selectedFileRelativePath;

  const AndroidSafTreeAccess({
    required this.treeUri,
    required this.selectedFileUri,
    this.treeDocumentId,
    this.selectedFileDocumentId,
    this.selectedFileRelativePath,
  });

  factory AndroidSafTreeAccess.fromMap(Map<Object?, Object?> map) {
    return AndroidSafTreeAccess(
      treeUri: (map['treeUri'] as String?) ?? '',
      treeDocumentId: map['treeDocumentId'] as String?,
      selectedFileUri: (map['selectedFileUri'] as String?) ?? '',
      selectedFileDocumentId: map['selectedFileDocumentId'] as String?,
      selectedFileRelativePath: map['selectedFileRelativePath'] as String?,
    );
  }
}

/// Result of selecting a directory via the Android SAF tree picker.
class AndroidSafDirectoryAccess {
  final String treeUri;
  final String? treeDocumentId;

  const AndroidSafDirectoryAccess({required this.treeUri, this.treeDocumentId});

  factory AndroidSafDirectoryAccess.fromMap(Map<Object?, Object?> map) {
    return AndroidSafDirectoryAccess(
      treeUri: (map['treeUri'] as String?) ?? '',
      treeDocumentId: map['treeDocumentId'] as String?,
    );
  }
}

/// Why a Storage Access Framework operation failed.
///
/// SAF reads return `null` for both "this file is not there" and "the provider
/// blew up", which left crash reports saying a file could not be read without
/// saying why. This carries the reason alongside the null so it can reach
/// Sentry and the user-facing message.
///
/// Deliberately free of file paths and user content: [operation], [code] and
/// [stage] are fixed strings, [authority] names the document provider (e.g.
/// `com.android.externalstorage.documents`), and [message] is the platform
/// exception class and message.
@immutable
class AndroidSafFailure {
  const AndroidSafFailure({
    required this.operation,
    required this.code,
    this.message,
    this.authority,
    this.stage,
  });

  /// The service method that failed, e.g. `readBytesFromTreePath`.
  final String operation;

  /// Platform error code, e.g. `saf_document_not_found`.
  final String code;

  /// Platform exception class and message, when one was reported.
  final String? message;

  /// Authority of the document provider backing the tree, when known.
  final String? authority;

  /// Which step failed: `resolve`, `open` or `read`.
  final String? stage;

  factory AndroidSafFailure.fromPlatformException(
    String operation,
    PlatformException e,
  ) {
    final details = e.details;
    final map = details is Map ? details : const <Object?, Object?>{};
    return AndroidSafFailure(
      operation: operation,
      code: e.code,
      message: e.message,
      authority: map['authority'] as String?,
      stage: map['stage'] as String?,
    );
  }

  @override
  String toString() {
    final parts = <String>[
      '$operation failed ($code)',
      if (stage != null) 'stage=$stage',
      if (authority != null) 'provider=$authority',
      if (message != null && message!.isNotEmpty) message!,
    ];
    return parts.join(' · ');
  }
}

/// A single document picked with the system file picker.
class AndroidSafDocument {
  final String uri;
  final String? displayName;
  final int sizeBytes;

  const AndroidSafDocument({
    required this.uri,
    this.displayName,
    required this.sizeBytes,
  });
}

/// A directory tree the native zip writer walks: every file under [path]
/// becomes an entry named `prefix + relativePath`.
class ZipRoot {
  final String path;
  final String prefix;
  const ZipRoot(this.path, this.prefix);

  Map<String, Object?> toMap() => {'path': path, 'prefix': prefix};
}

/// One explicit file for the native zip writer, with its deflate level.
class ZipFileEntry {
  final String path;
  final String name;
  final int level;
  const ZipFileEntry(this.path, this.name, this.level);

  Map<String, Object?> toMap() => {'path': path, 'name': name, 'level': level};
}

class ZipWriteResult {
  /// Document URI for a tree target, the file path for a file target.
  final String location;
  final int bytes;
  final int entries;
  final int skippedFiles;
  final bool cancelled;

  const ZipWriteResult({
    required this.location,
    required this.bytes,
    required this.entries,
    required this.skippedFiles,
    required this.cancelled,
  });
}

/// Result of peeking at one entry of a zip without reading the rest.
class ZipPeek {
  /// False when the input does not start with a zip signature at all.
  final bool isZip;
  final String? text;
  const ZipPeek({required this.isZip, this.text});
}

/// Android Storage Access Framework helper.
///
/// Provides persisted tree access and tree-relative file reads so the app can
/// read mokuro HTML/JSON and image files without MANAGE_EXTERNAL_STORAGE,
/// plus the streaming zip primitives behind the full backup.
class AndroidSafService {
  static const MethodChannel _channel = MethodChannel('mekuru/android_saf');

  /// Records [failure] as a Sentry breadcrumb and returns it.
  ///
  /// Every SAF entry point funnels failures through here so that even callers
  /// that legitimately ignore the reason still leave a trail on the next crash.
  static AndroidSafFailure _report(AndroidSafFailure failure) {
    debugPrint('[AndroidSaf] $failure');
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'saf',
        message: failure.toString(),
        level: SentryLevel.warning,
        data: {
          'operation': failure.operation,
          'code': failure.code,
          if (failure.stage != null) 'stage': failure.stage,
          if (failure.authority != null) 'authority': failure.authority,
        },
      ),
    );
    return failure;
  }

  static bool isContentUri(String value) =>
      value.toLowerCase().startsWith('content://');

  /// Lets the user pick a directory via SAF and persists the tree grant.
  static Future<AndroidSafDirectoryAccess?> pickDirectory() async {
    try {
      final result = await _channel.invokeMethod<Object?>('pickDirectory');
      if (result == null || result is! Map) return null;
      final access = AndroidSafDirectoryAccess.fromMap(
        Map<Object?, Object?>.from(result),
      );
      if (access.treeUri.isEmpty) return null;
      return access;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[AndroidSaf] pickDirectory failed: $e');
      rethrow;
    }
  }

  /// Prompts the user to grant folder access (via SAF tree picker) for the
  /// directory containing the picked document, and persists the permission.
  static Future<AndroidSafTreeAccess?> requestDirectoryAccessForDocument(
    String documentUri,
  ) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'requestDirectoryAccessForDocument',
        {'documentUri': documentUri},
      );
      if (result == null) return null;
      if (result is! Map) return null;
      final access = AndroidSafTreeAccess.fromMap(
        Map<Object?, Object?>.from(result),
      );
      if (access.treeUri.isEmpty || access.selectedFileUri.isEmpty) {
        return null;
      }
      return access;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[AndroidSaf] requestDirectoryAccessForDocument failed: $e');
      rethrow;
    }
  }

  static Future<Uint8List?> readBytesFromUri(
    String uri, {
    void Function(AndroidSafFailure failure)? onFailure,
  }) async {
    return _read<Uint8List>(
      operation: 'readBytesFromUri',
      invoke: () =>
          _channel.invokeMethod<Uint8List>('readBytesFromUri', {'uri': uri}),
      onFailure: onFailure,
    );
  }

  static Future<String?> readTextFromUri(
    String uri, {
    void Function(AndroidSafFailure failure)? onFailure,
  }) async {
    return _read<String>(
      operation: 'readTextFromUri',
      invoke: () =>
          _channel.invokeMethod<String>('readTextFromUri', {'uri': uri}),
      onFailure: onFailure,
    );
  }

  static Future<Uint8List?> readBytesFromTreePath(
    String treeUri,
    String relativePath, {
    void Function(AndroidSafFailure failure)? onFailure,
  }) async {
    return _read<Uint8List>(
      operation: 'readBytesFromTreePath',
      invoke: () => _channel.invokeMethod<Uint8List>('readBytesFromTreePath', {
        'treeUri': treeUri,
        'relativePath': relativePath,
      }),
      onFailure: onFailure,
    );
  }

  static Future<String?> readTextFromTreePath(
    String treeUri,
    String relativePath, {
    void Function(AndroidSafFailure failure)? onFailure,
  }) async {
    return _read<String>(
      operation: 'readTextFromTreePath',
      invoke: () => _channel.invokeMethod<String>('readTextFromTreePath', {
        'treeUri': treeUri,
        'relativePath': relativePath,
      }),
      onFailure: onFailure,
    );
  }

  /// Runs [invoke], returning `null` on failure after reporting the reason.
  ///
  /// Reads stay null-returning so callers that treat a missing file as normal
  /// keep working; the reason is what changes, reaching Sentry always and
  /// [onFailure] when the caller wants to surface it.
  static Future<T?> _read<T>({
    required String operation,
    required Future<T?> Function() invoke,
    void Function(AndroidSafFailure failure)? onFailure,
  }) async {
    try {
      return await invoke();
    } on MissingPluginException {
      onFailure?.call(
        _report(
          AndroidSafFailure(
            operation: operation,
            code: 'missing_plugin',
            message: 'The SAF method channel is not registered',
          ),
        ),
      );
      return null;
    } on PlatformException catch (e) {
      onFailure?.call(
        _report(AndroidSafFailure.fromPlatformException(operation, e)),
      );
      return null;
    }
  }

  static Future<bool> existsInTreePath(
    String treeUri,
    String relativePath,
  ) async {
    try {
      return await _channel.invokeMethod<bool>('existsInTreePath', {
            'treeUri': treeUri,
            'relativePath': relativePath,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      _report(AndroidSafFailure.fromPlatformException('existsInTreePath', e));
      return false;
    }
  }

  static Future<List<String>> listNamesInTreeDir(
    String treeUri, {
    String relativePath = '',
  }) async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'listNamesInTreeDir',
        {'treeUri': treeUri, 'relativePath': relativePath},
      );
      if (result == null) return const [];
      return result.whereType<String>().toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      _report(AndroidSafFailure.fromPlatformException('listNamesInTreeDir', e));
      return const [];
    }
  }

  static Future<String?> getDocumentUriInTree(
    String treeUri,
    String relativePath,
  ) async {
    try {
      return await _channel.invokeMethod<String>('getDocumentUriInTree', {
        'treeUri': treeUri,
        'relativePath': relativePath,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      _report(
        AndroidSafFailure.fromPlatformException('getDocumentUriInTree', e),
      );
      return null;
    }
  }

  // ──────────────── Full backup: picker, space, streaming zip ────────────────

  /// Lets the user pick one document. Returns null when cancelled or when
  /// the channel is not registered.
  static Future<AndroidSafDocument?> pickDocument({
    List<String> mimeTypes = const [
      'application/zip',
      'application/octet-stream',
    ],
  }) async {
    try {
      final result = await _channel.invokeMethod<Object?>('pickDocument', {
        'mimeTypes': mimeTypes,
      });
      if (result == null || result is! Map) return null;
      final uri = result['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return AndroidSafDocument(
        uri: uri,
        displayName: result['displayName'] as String?,
        sizeBytes: (result['sizeBytes'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[AndroidSaf] pickDocument failed: $e');
      rethrow;
    }
  }

  /// Usable bytes on the volume holding [path]; null when unknown.
  static Future<int?> getFreeBytes(String path) => _read<int>(
    operation: 'getFreeBytes',
    invoke: () async {
      final value = await _channel.invokeMethod<Object?>('getFreeBytes', {
        'path': path,
      });
      return (value as num?)?.toInt();
    },
  );

  /// Total bytes and file count under [path], pruning [excludeDirNames].
  static Future<({int bytes, int files})?> measureTree(
    String path, {
    List<String> excludeDirNames = const [],
  }) => _read<({int bytes, int files})>(
    operation: 'measureTree',
    invoke: () async {
      final value = await _channel.invokeMethod<Object?>('measureTree', {
        'path': path,
        'excludeDirNames': excludeDirNames,
      });
      if (value is! Map) return null;
      return (
        bytes: (value['bytes'] as num?)?.toInt() ?? 0,
        files: (value['files'] as num?)?.toInt() ?? 0,
      );
    },
  );

  /// Streams a zip of [files] then [roots] into a new document named
  /// [displayName] inside the SAF tree. Throws [PlatformException] on failure.
  static Future<ZipWriteResult> writeZipToTree({
    required String treeUri,
    required String displayName,
    required List<ZipRoot> roots,
    required List<ZipFileEntry> files,
    List<String> excludeDirNames = const [],
  }) => _invoke('writeZipToTree', () async {
    final result = await _channel.invokeMethod<Object?>('writeZipToTree', {
      'treeUri': treeUri,
      'displayName': displayName,
      'roots': roots.map((r) => r.toMap()).toList(),
      'files': files.map((f) => f.toMap()).toList(),
      'excludeDirNames': excludeDirNames,
    });
    return _zipWriteResult(result, fallbackLocation: displayName);
  });

  /// Same as [writeZipToTree] but onto a plain file path (tests, fallbacks).
  static Future<ZipWriteResult> writeZipToFile({
    required String path,
    required List<ZipRoot> roots,
    required List<ZipFileEntry> files,
    List<String> excludeDirNames = const [],
  }) => _invoke('writeZipToFile', () async {
    final result = await _channel.invokeMethod<Object?>('writeZipToFile', {
      'path': path,
      'roots': roots.map((r) => r.toMap()).toList(),
      'files': files.map((f) => f.toMap()).toList(),
      'excludeDirNames': excludeDirNames,
    });
    return _zipWriteResult(result, fallbackLocation: path);
  });

  /// Reads one entry's text from the start of a zip without reading the
  /// rest. Exactly one of [uri] or [path] must be given.
  static Future<ZipPeek?> peekZipEntryText({
    String? uri,
    String? path,
    required String name,
  }) => _read<ZipPeek>(
    operation: 'peekZipEntryText',
    invoke: () async {
      final value = await _channel.invokeMethod<Object?>('peekZipEntryText', {
        'uri': ?uri,
        'path': ?path,
        'name': name,
      });
      if (value is! Map) return null;
      return ZipPeek(
        isZip: value['isZip'] == true,
        text: value['text'] as String?,
      );
    },
  );

  /// Extracts the archive at [uri] under [destPath]; returns the entry count,
  /// or null when cancelled. Throws [PlatformException] on failure.
  static Future<int?> extractZipFromUri({
    required String uri,
    required String destPath,
  }) => _invoke('extractZipFromUri', () async {
    final value = await _channel.invokeMethod<Object?>('extractZipFromUri', {
      'uri': uri,
      'destPath': destPath,
    });
    return _extractedEntries(value);
  });

  /// Same as [extractZipFromUri] for a plain file path.
  static Future<int?> extractZipFromFile({
    required String path,
    required String destPath,
  }) => _invoke('extractZipFromFile', () async {
    final value = await _channel.invokeMethod<Object?>('extractZipFromFile', {
      'path': path,
      'destPath': destPath,
    });
    return _extractedEntries(value);
  });

  /// Progress of the zip operation in flight as (done, total) bytes.
  static Future<(int done, int total)> zipProgress() async {
    try {
      final value = await _channel.invokeMethod<Object?>('zipProgress');
      if (value is! Map) return (0, 0);
      return (
        (value['done'] as num?)?.toInt() ?? 0,
        (value['total'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return (0, 0);
    } on PlatformException {
      return (0, 0);
    }
  }

  /// Asks the zip operation in flight to stop at its next buffer.
  static Future<void> cancelZip() async {
    try {
      await _channel.invokeMethod<void>('cancelZip');
    } on MissingPluginException {
      // Nothing to cancel without the channel.
    }
  }

  /// Polls [zipProgress] while listened to.
  static Stream<(int done, int total)> pollZipProgress({
    Duration every = const Duration(milliseconds: 500),
  }) => Stream.periodic(every).asyncMap((_) => zipProgress());

  static ZipWriteResult _zipWriteResult(
    Object? value, {
    required String fallbackLocation,
  }) {
    final map = value is Map ? value : const <Object?, Object?>{};
    return ZipWriteResult(
      location: (map['documentUri'] as String?) ?? fallbackLocation,
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      entries: (map['entries'] as num?)?.toInt() ?? 0,
      skippedFiles: (map['skippedFiles'] as num?)?.toInt() ?? 0,
      cancelled: map['cancelled'] == true,
    );
  }

  static int? _extractedEntries(Object? value) {
    if (value is! Map) return null;
    if (value['cancelled'] == true) return null;
    return (value['entries'] as num?)?.toInt() ?? 0;
  }

  /// Runs [invoke], leaving a breadcrumb for a platform failure and
  /// rethrowing it: writes and extractions must surface their errors.
  static Future<T> _invoke<T>(
    String operation,
    Future<T> Function() invoke,
  ) async {
    try {
      return await invoke();
    } on PlatformException catch (e) {
      _report(AndroidSafFailure.fromPlatformException(operation, e));
      rethrow;
    }
  }
}
