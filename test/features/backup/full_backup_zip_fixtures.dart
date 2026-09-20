import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart' show InputFileStream, ZipDecoder;
import 'package:mekuru/features/backup/data/services/full_backup_zip.dart';

const fixtureMtime = 1700000000000;

List<int> randomBytes(int seed, int length) {
  final random = Random(seed);
  return List.generate(length, (_) => random.nextInt(256));
}

/// Writes [entries] as a complete archive with the job's own writer: `.jpg`
/// stored (level 0), the rest deflated, as the Kotlin fixtures do.
Future<File> buildArchive(
  File file,
  List<(String, List<int>)> entries, {
  bool forceZip64 = false,
}) async {
  file.parent.createSync(recursive: true);
  final out = await file.open(mode: FileMode.write);
  try {
    final writer = FullBackupZipWriter(out, forceZip64: forceZip64);
    for (final (name, bytes) in entries) {
      await writer.add(
        name,
        fixtureMtime,
        name.endsWith('.jpg') ? 0 : 6,
        Stream.value(bytes),
      );
    }
    await writer.finish();
  } finally {
    await out.close();
  }
  return file;
}

/// Entry name → bytes, in archive order, as `package:archive` reads them.
Map<String, List<int>> readZip(File file) {
  final input = InputFileStream(file.path);
  try {
    return {
      for (final entry in ZipDecoder().decodeStream(input))
        entry.name: entry.readBytes()!,
    };
  } finally {
    input.closeSync();
  }
}

/// Flips one payload byte of the entry called [name].
void corruptEntry(File zip, String name) {
  final header = readZipDirectory(
    zip.path,
  ).firstWhere((h) => h.filename == name);
  final raf = zip.openSync(mode: FileMode.append);
  try {
    // Past the local header, its name and the first deflate block header.
    final at = header.localHeaderOffset + 30 + utf8.encode(name).length + 16;
    raf.setPositionSync(at);
    final byte = raf.readByteSync();
    raf.setPositionSync(at);
    raf.writeByteSync(byte ^ 0x55);
  } finally {
    raf.closeSync();
  }
}
