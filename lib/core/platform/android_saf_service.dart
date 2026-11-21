// ignore_for_file: discarded_futures
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

/// A file inside a folder the user granted Mekuru access to.
class SafTreeFile {
  final String name;

  /// The document URI a `ContentResolver` opens; valid while the grant is.
  final String uri;

  /// Bytes, or -1 when the provider did not report a size.
  final int size;

  /// Milliseconds since the epoch, or 0 when unknown.
  final int lastModified;

  const SafTreeFile({
    required this.name,
    required this.uri,
    required this.size,
    required this.lastModified,
  });
}

/// Android Storage Access Framework helper.
///
/// Provides persisted tree access and tree-relative file reads so the app can
/// read mokuro HTML/JSON and image files without MANAGE_EXTERNAL_STORAGE,
/// plus the free-space query behind the full backup. The pickers and the
/// save dialog are in file_pick.dart.
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

  /// Lists the files (not folders) directly inside [relativePath] of a
  /// granted tree, with their document URIs and sizes. Empty when the grant
  /// is gone or the folder cannot be read.
  static Future<List<SafTreeFile>> listFilesInTreeDir(
    String treeUri,
    String relativePath,
  ) async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'listFilesInTreeDir',
        {'treeUri': treeUri, 'relativePath': relativePath},
      );
      return [
        for (final item in result ?? const <Object?>[])
          if (item is Map && item['name'] is String && item['uri'] is String)
            SafTreeFile(
              name: item['name'] as String,
              uri: item['uri'] as String,
              size: (item['size'] as num?)?.toInt() ?? -1,
              lastModified: (item['lastModified'] as num?)?.toInt() ?? 0,
            ),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      _report(AndroidSafFailure.fromPlatformException('listFilesInTreeDir', e));
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

  // ──────────────── Full backup: free space ────────────────

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
}
