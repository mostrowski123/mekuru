import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// Android Storage Access Framework helper.
///
/// Provides persisted tree access and tree-relative file reads so the app can
/// read mokuro HTML/JSON and image files without MANAGE_EXTERNAL_STORAGE.
class AndroidSafService {
  static const MethodChannel _channel = MethodChannel('mekuru/android_saf');

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

  static Future<Uint8List?> readBytesFromUri(String uri) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'readBytesFromUri',
        {'uri': uri},
      );
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[AndroidSaf] readBytesFromUri failed for $uri: $e');
      return null;
    }
  }

  static Future<String?> readTextFromUri(String uri) async {
    try {
      return await _channel.invokeMethod<String>('readTextFromUri', {
        'uri': uri,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[AndroidSaf] readTextFromUri failed for $uri: $e');
      return null;
    }
  }

  static Future<Uint8List?> readBytesFromTreePath(
    String treeUri,
    String relativePath,
  ) async {
    try {
      return await _channel.invokeMethod<Uint8List>('readBytesFromTreePath', {
        'treeUri': treeUri,
        'relativePath': relativePath,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint(
        '[AndroidSaf] readBytesFromTreePath failed for $relativePath: $e',
      );
      return null;
    }
  }

  static Future<String?> readTextFromTreePath(
    String treeUri,
    String relativePath,
  ) async {
    try {
      return await _channel.invokeMethod<String>('readTextFromTreePath', {
        'treeUri': treeUri,
        'relativePath': relativePath,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint(
        '[AndroidSaf] readTextFromTreePath failed for $relativePath: $e',
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
      debugPrint('[AndroidSaf] existsInTreePath failed for $relativePath: $e');
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
      debugPrint(
        '[AndroidSaf] listNamesInTreeDir failed for $relativePath: $e',
      );
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
      debugPrint(
        '[AndroidSaf] getDocumentUriInTree failed for $relativePath: $e',
      );
      return null;
    }
  }
}
