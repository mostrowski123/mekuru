/// The system file dialogs: picking files and folders, and saving a finished
/// file. Nothing else opens one, so every failure a dialog is known to have
/// is handled here once and reaches every screen as a [FileDialogResult].
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;

const _saf = MethodChannel('mekuru/android_saf');
const _iosFiles = MethodChannel('mekuru/ios_files');

/// What a system file dialog came back with.
sealed class FileDialogResult<T> {
  const FileDialogResult();

  /// The same outcome, with a chosen value turned into [convert]'s.
  FileDialogResult<R> map<R>(R Function(T value) convert) => switch (this) {
    FileDialogDone(:final value) => FileDialogDone(convert(value)),
    FileDialogFailed(:final failure) => FileDialogFailed(failure),
    FileDialogCancelled() => FileDialogCancelled(),
  };
}

/// The user chose: [value] is what they picked, or nothing for a save.
final class FileDialogDone<T> extends FileDialogResult<T> {
  const FileDialogDone(this.value);
  final T value;
}

/// The user closed the dialog, or there was nothing to show it from: one
/// was already open (a second tap while the first pick copies its file), or
/// the app went to the background mid-tap. Nothing to say.
final class FileDialogCancelled<T> extends FileDialogResult<T> {
  const FileDialogCancelled();
}

/// The dialog could not do it. Show [failure]'s message.
final class FileDialogFailed<T> extends FileDialogResult<T> {
  const FileDialogFailed(this.failure);
  final FileDialogFailure failure;
}

enum FileDialogFailure {
  /// No app on the device answers the system file picker (MEKURU-2Z: some
  /// e-readers).
  noPicker,

  /// The same, for the save dialog.
  noSaveDialog,

  /// Android's picker copies each pick into the cache under its own name,
  /// which fails past 255 bytes (about 85 Japanese characters) and drops
  /// the whole selection (MEKURU-2R).
  nameTooLong;

  String message(AppLocalizations l10n) => switch (this) {
    noPicker => l10n.commonNoFilePicker,
    noSaveDialog => l10n.commonNoSaveDialog,
    nameTooLong => l10n.libraryFileNameTooLong,
  };
}

/// Files to open, as paths to the copies the picker made for the app: any
/// file, or those with one of [extensions], or [images] (the photo library
/// on iOS). One file unless [multiple].
Future<FileDialogResult<List<String>>> pickFiles({
  List<String>? extensions,
  bool images = false,
  bool multiple = false,
}) {
  assert(extensions == null || !images);
  final type = images
      ? FileType.image
      : extensions == null
      ? FileType.any
      : FileType.custom;
  return _open(() async {
    final paths = multiple
        ? [
            ...?(await FilePicker.pickFiles(
              type: type,
              allowedExtensions: extensions,
            ))?.files.map((f) => f.path).nonNulls,
          ]
        : [
            ?(await FilePicker.pickFile(
              type: type,
              allowedExtensions: extensions,
            ))?.path,
          ];
    return paths.isEmpty ? null : paths;
  });
}

/// A folder picked through SAF: its tree URI, which a persisted grant lets
/// the app read.
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

/// A document picked through SAF: its URI and size.
class AndroidSafDocument {
  final String uri;
  final int sizeBytes;

  const AndroidSafDocument({required this.uri, required this.sizeBytes});
}

/// Android: a folder through SAF, with a persisted grant to read it.
Future<FileDialogResult<AndroidSafDirectoryAccess>> pickAndroidFolder() =>
    _open(() async {
      final picked = await _saf.invokeMethod<Map<Object?, Object?>>(
        'pickDirectory',
      );
      if (picked == null) return null;
      final access = AndroidSafDirectoryAccess.fromMap(picked);
      return access.treeUri.isEmpty ? null : access;
    });

/// Android: a zip by its document URI, with its size: the full backup's
/// restore, which reads the archive where it is.
Future<FileDialogResult<AndroidSafDocument>> pickAndroidZip() =>
    _open(() async {
      final picked = await _saf.invokeMethod<Map<Object?, Object?>>(
        'pickDocument',
        {
          'mimeTypes': ['application/zip', 'application/octet-stream'],
        },
      );
      final uri = picked?['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return AndroidSafDocument(
        uri: uri,
        sizeBytes: (picked!['sizeBytes'] as num?)?.toInt() ?? 0,
      );
    });

/// iOS: a folder's path. Its security scope stays open until the next
/// folder pick, so it can be read after this returns. Not file_picker's
/// folder mode: on iOS a cancelled folder pick leaves file_picker in it and
/// breaks every later file pick (MEKURU-1Y).
Future<FileDialogResult<String>> pickIosFolder() =>
    _open(() => _iosFiles.invokeMethod<String>('pickFolder'));

/// iOS: a copy of a zip in the app's temp folder, the caller's to delete.
Future<FileDialogResult<String>> pickIosZip() =>
    _open(() => _iosFiles.invokeMethod<String>('pickZip'));

/// Lets the user choose where the finished file at [path] goes. The dialog
/// offers the file's own name, so name it as the user should see it. Only
/// the path crosses the channel, never the file: on iOS the document picker
/// moves the file, on Android the save dialog streams a copy natively.
///
/// The file is gone afterwards, whatever happened, unless [keepIfNotSaved]
/// and it was not saved: then it stays for the caller to offer again.
Future<FileDialogResult<void>> saveFile(
  String path, {
  required String mimeType,
  bool keepIfNotSaved = false,
}) async {
  var saved = false;
  try {
    final result = await _open(() async {
      final answer = defaultTargetPlatform == TargetPlatform.iOS
          ? await _iosFiles.invokeMethod<bool>('exportFile', path)
          : await _saf.invokeMethod<bool>('saveDocument', {
              'path': path,
              'name': p.basename(path),
              'mimeType': mimeType,
            });
      return answer == true ? true : null;
    }, noApp: FileDialogFailure.noSaveDialog);
    saved = result is FileDialogDone;
    return result.map((_) {});
  } finally {
    if (saved || !keepIfNotSaved) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Moved out by the iOS document picker.
      }
    }
  }
}

/// Runs a dialog whose null answer means cancelled, and maps every failure
/// it is known to have. Anything else is a bug and is rethrown.
Future<FileDialogResult<T>> _open<T extends Object>(
  Future<T?> Function() dialog, {
  FileDialogFailure noApp = FileDialogFailure.noPicker,
}) async {
  try {
    final value = await dialog();
    return value == null ? FileDialogCancelled() : FileDialogDone(value);
  } on MissingPluginException {
    return FileDialogFailed(noApp);
  } on PlatformException catch (e, stack) {
    return switch (e.code) {
      // A dialog already open: file_picker's on Android (already_active)
      // and iOS (multiple_request), Mekuru's own on Android (busy) and iOS
      // (picker_unavailable, also when there is no screen to show it on).
      // No activity to show it from, or the picker came back without a
      // file: the app went to the background mid-tap (unknown_activity,
      // no_activity).
      'already_active' ||
      'multiple_request' ||
      'busy' ||
      'picker_unavailable' ||
      'unknown_activity' ||
      'no_activity' => FileDialogCancelled(),
      'explorer_not_found' => FileDialogFailed(noApp),
      'file_picker_error'
          when e.message?.contains('File name too long') ?? false =>
        FileDialogFailed(FileDialogFailure.nameTooLong),
      _ => Error.throwWithStackTrace(e, stack),
    };
  }
}
