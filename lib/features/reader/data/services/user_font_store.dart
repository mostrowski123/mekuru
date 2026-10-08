import 'dart:io';

import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/backup/data/models/zip_folder_name.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A font file the user added, kept in Mekuru's fonts folder.
class UserFont {
  const UserFont({required this.fileName});

  /// The name in the fonts folder; settings store only this.
  final String fileName;

  /// The file name without its extension.
  String get displayName => p.basenameWithoutExtension(fileName);

  @override
  bool operator ==(Object other) =>
      other is UserFont && other.fileName == fileName;

  @override
  int get hashCode => fileName.hashCode;

  @override
  String toString() => 'UserFont($fileName)';
}

enum FontFileFormat {
  trueType('ttf'),
  openType('otf'),
  woff('woff'),
  woff2('woff2');

  const FontFileFormat(this.extension);

  /// The extension a stored font of this format gets.
  final String extension;
}

enum UserFontImportError { notAFont, collection, tooLarge }

class UserFontImportException implements Exception {
  const UserFontImportException(this.error);

  final UserFontImportError error;

  @override
  String toString() => 'UserFontImportException(${error.name})';
}

/// Larger fonts are refused: the reader holds the whole font in the WebView
/// and sends it there as base64 every time a book opens.
const int maxUserFontBytes = 50 * 1024 * 1024;

/// Identifies a font file by its first four bytes. Collections (`ttcf`) are
/// refused: neither WebView engine is guaranteed to load one.
FontFileFormat detectFontFormat(List<int> head) {
  if (head.length < 4) {
    throw const UserFontImportException(UserFontImportError.notAFont);
  }
  if (head[0] == 0 && head[1] == 1 && head[2] == 0 && head[3] == 0) {
    return FontFileFormat.trueType;
  }
  return switch (String.fromCharCodes(head.take(4))) {
    'true' => FontFileFormat.trueType,
    'OTTO' => FontFileFormat.openType,
    'wOFF' => FontFileFormat.woff,
    'wOF2' => FontFileFormat.woff2,
    'ttcf' => throw const UserFontImportException(
      UserFontImportError.collection,
    ),
    _ => throw const UserFontImportException(UserFontImportError.notAFont),
  };
}

/// The fonts the user added: `<app support>/fonts/`, flat. The folder
/// listing is the font list; there is no database table.
class UserFontStore {
  UserFontStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  static const dirName = 'fonts';

  final Future<Directory> Function() _root;

  Future<Directory> _dir() async =>
      Directory(p.join((await _root()).path, dirName));

  /// Sorted by display name, ignoring case; half-copied `.tmp` files are
  /// never listed.
  Future<List<UserFont>> list() async {
    final dir = await _dir();
    if (!await dir.exists()) return const [];
    final fonts = <UserFont>[
      await for (final entity in dir.list(followLinks: false))
        if (entity is File && !entity.path.endsWith('.tmp'))
          UserFont(fileName: p.basename(entity.path)),
    ];
    fonts.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return fonts;
  }

  /// Checks [sourcePath] and copies it in. The extension follows the
  /// detected format, not the picked name. Throws [UserFontImportException]
  /// for a file that is not an accepted font, [FileSystemException] when the
  /// copy fails.
  Future<UserFont> import(String sourcePath) async {
    final source = File(sourcePath);
    if (await source.length() > maxUserFontBytes) {
      throw const UserFontImportException(UserFontImportError.tooLarge);
    }
    final head = await source.openRead(0, 4).expand((chunk) => chunk).toList();
    final format = detectFontFormat(head);

    final dir = await _dir();
    await dir.create(recursive: true);
    // The user's name, Unicode included, made safe and short enough for
    // every file system (the same rule as the full backup's folder names).
    final base = zipFolderName(
      p.basenameWithoutExtension(sourcePath),
      fallback: 'font',
    );
    final extension = format.extension;
    var fileName = '$base.$extension';
    for (var n = 2; File(p.join(dir.path, fileName)).existsSync(); n++) {
      fileName = '$base ($n).$extension';
    }

    // A font never appears half-copied.
    await copyFileAtomic(source, File(p.join(dir.path, fileName)));
    return UserFont(fileName: fileName);
  }

  Future<void> delete(String fileName) async {
    await (await fileFor(fileName))?.delete();
  }

  /// The font's file, or null when [fileName] is null, not a plain name in
  /// the folder, or missing.
  Future<File?> fileFor(String? fileName) async {
    if (fileName == null ||
        fileName.isEmpty ||
        fileName != p.basename(fileName) ||
        fileName.startsWith('.') ||
        fileName.endsWith('.tmp')) {
      return null;
    }
    final file = File(p.join((await _dir()).path, fileName));
    return await file.exists() ? file : null;
  }
}
