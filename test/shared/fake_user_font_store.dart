import 'dart:io';

import 'package:mekuru/features/reader/data/services/user_font_store.dart';

/// In-memory fonts for widget tests: no file system, no picker.
class FakeUserFontStore extends UserFontStore {
  FakeUserFontStore([Iterable<String> fileNames = const []])
    : fileNames = [...fileNames];

  final List<String> fileNames;

  /// What the next [import] does: the name to add, or an error to throw.
  Object nextImport = 'Added.ttf';

  @override
  Future<List<UserFont>> list() async => [
    for (final name in fileNames) UserFont(fileName: name),
  ];

  @override
  Future<UserFont> import(String sourcePath) async {
    final next = nextImport;
    if (next is Exception) throw next;
    fileNames.add(next as String);
    return UserFont(fileName: next);
  }

  @override
  Future<void> delete(String fileName) async => fileNames.remove(fileName);

  @override
  Future<File?> fileFor(String? fileName) async =>
      fileNames.contains(fileName) ? File('/fake/fonts/$fileName') : null;
}
