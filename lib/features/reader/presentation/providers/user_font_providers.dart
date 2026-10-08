import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/data/services/user_font_store.dart';

final userFontStoreProvider = Provider<UserFontStore>((ref) => UserFontStore());

/// The fonts the user added. Invalidate after an import or a removal.
final userFontsProvider = FutureProvider<List<UserFont>>(
  (ref) => ref.watch(userFontStoreProvider).list(),
);

/// Opens the system file picker for a font; tests replace it.
final userFontFilePickerProvider = Provider<Future<String?> Function()>(
  (ref) => pickUserFontFile,
);

/// The picked file's path, or null when the user cancelled.
Future<String?> pickUserFontFile() async {
  try {
    // Any file: extension filters miss font MIME types on some Android
    // OEMs, and iOS has no file type for .woff2. The store checks the bytes.
    final picked = await FilePicker.pickFile(type: FileType.any);
    return picked?.path;
  } on PlatformException catch (e) {
    // already_active: a second tap while the first pick is still copying
    // its file. unknown_activity: the picker came back without a file.
    if (e.code != 'already_active' && e.code != 'unknown_activity') rethrow;
    return null;
  }
}
