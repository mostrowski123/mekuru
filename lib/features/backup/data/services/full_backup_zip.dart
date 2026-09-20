import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart'
    show InputFileStream, ZipDirectory, ZipFileHeader, getCrc32;
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:path/path.dart' as p;

// The zip side of the in-process (iOS) full-backup job: Dart ports of the
// Kotlin `ZipNameMapper`, `ZipPeek` and `ResumableZipWriter` (minus resume),
// plus a streaming entry extractor. No Flutter imports. Bytes go through
// `dart:io` zlib streams, never `package:archive`'s codecs: its encoder and
// decoder both hold a whole deflated entry in memory, and the database
// snapshot can be gigabytes. `archive` only parses the central directory.

/// An entry name that would land outside the staging directory.
class UnsafeZipEntryException implements Exception {
  const UnsafeZipEntryException();
}

/// The archive cannot be read, or an entry fails its size or CRC check.
class CorruptZipException implements Exception {
  const CorruptZipException();
}

/// Maps archive entry names back to the on-device layout under the staging
/// directory using the manifest's `folders` map (zip prefix → import
/// directory name). Entries that belong to no known place are skipped rather
/// than failing a multi-gigabyte restore.
class ZipNameMapper {
  ZipNameMapper(Map<String, String> folders)
    : _folders = {
        for (final e in folders.entries)
          (e.key.endsWith('/') ? e.key : '${e.key}/'): e.value,
      };

  final Map<String, String> _folders;

  /// `BookRepository.booksSegment`, spelled out to keep this file light.
  static const _booksDir = 'books';

  /// Path relative to staging, or null when the entry is not restored.
  String? map(String name) {
    if (name.endsWith('/')) return null;
    switch (name) {
      case FullBackupManifest.manifestEntry || FullBackupManifest.readmeEntry:
        return null;
      case FullBackupManifest.databaseEntry:
        return AppDatabase.databaseFileName;
      case FullBackupManifest.settingsEntry:
        return FullBackupManifest.settingsFileName;
    }
    if (name.startsWith(FullBackupManifest.coversPrefix)) {
      final rest = name.substring(FullBackupManifest.coversPrefix.length);
      if (rest.isEmpty || rest.contains('/')) return null;
      return '$_booksDir/$rest';
    }
    if (name.startsWith(FullBackupManifest.unidicPrefix)) {
      final rest = name.substring(FullBackupManifest.unidicPrefix.length);
      if (rest.isEmpty) return null;
      return '${FullBackupManifest.unidicDirName}/$rest';
    }
    for (final MapEntry(key: prefix, value: dir) in _folders.entries) {
      if (!name.startsWith(prefix)) continue;
      final rest = name.substring(prefix.length);
      if (rest.isEmpty) return null;
      return '$_booksDir/$dir/$rest';
    }
    return null;
  }

  /// Zip-slip guard: [rel] must stay inside [dest]. Lexical only; the job
  /// extracts into a directory it just created, so there are no symlinks to
  /// resolve.
  static String resolveInside(String dest, String rel) {
    final escapes =
        rel.isEmpty ||
        rel.startsWith('/') ||
        rel.startsWith(r'\') ||
        rel.split(_separators).contains('..');
    if (escapes) throw const UnsafeZipEntryException();
    return p.join(dest, rel);
  }

  static final _separators = RegExp(r'[/\\]');
}

// ──────────────── Peek ────────────────

/// What a restore learns about an archive before committing to it.
typedef ZipPeek = ({bool isZip, String? text, bool complete});

/// Bytes of tail that can hold an end-of-central-directory record.
const zipEndRecordTail = (64 << 10) + 22;

/// True when [tail] (the last [zipEndRecordTail] bytes of a file, or the
/// whole file if shorter) contains an end-of-central-directory signature: a
/// zip written to completion, as opposed to one cut short by a crash or an
/// interrupted copy.
bool zipHasEndRecord(List<int> tail) {
  for (var i = tail.length - 4; i >= 0; i--) {
    if (tail[i] == 0x50 &&
        tail[i + 1] == 0x4B &&
        tail[i + 2] == 0x05 &&
        tail[i + 3] == 0x06) {
      return true;
    }
  }
  return false;
}

/// Tells "not a zip at all" (a `.mekuru` JSON file picked by mistake) from a
/// zip, and returns the UTF-8 text of the entry called [name]: null when it
/// is absent, unreadable or larger than [maxBytes]. The first entry is read
/// from its local header alone, so a truncated archive still shows its
/// manifest; any other position needs the central directory.
Future<ZipPeek> peekZip(
  File file,
  String name, {
  int maxBytes = 1 << 20,
}) async {
  final raf = await file.open();
  try {
    final length = await raf.length();
    final head = await raf.read(30);
    if (head.length < 4 || _u32(head, 0) != _locSig) {
      return (isZip: false, text: null, complete: false);
    }
    final tail = math.min(length, zipEndRecordTail);
    await raf.setPosition(length - tail);
    final complete = zipHasEndRecord(await raf.read(tail));

    String? text;
    if (head.length == 30) {
      final nameLength = _u16(head, 26);
      await raf.setPosition(30);
      final first = utf8.decode(
        await raf.read(nameLength),
        allowMalformed: true,
      );
      if (first == name) {
        final csize = _u32(head, 18);
        text = await _entryText(
          file,
          start: 30 + nameLength + _u16(head, 28),
          method: _u16(head, 8),
          // Sizes live in a data descriptor (bit 3) or a ZIP64 extra.
          csize: _u16(head, 6) & 0x08 != 0 || csize == _magic32 ? null : csize,
          maxBytes: maxBytes,
        );
      } else if (complete) {
        final header = readZipDirectory(
          file.path,
        ).where((h) => h.filename == name).firstOrNull;
        if (header != null) {
          text = await _entryText(
            file,
            start: _dataOffset(raf, header),
            method: header.compressionMethod,
            csize: header.compressedSize,
            maxBytes: maxBytes,
          );
        }
      }
    }
    return (isZip: true, text: text, complete: complete);
  } finally {
    await raf.close();
  }
}

/// Inflates at most [maxBytes] of text. An unknown [csize] reads as far as a
/// text that size can reach; zlib ignores whatever follows the stream's end.
Future<String?> _entryText(
  File file, {
  required int start,
  required int method,
  required int? csize,
  required int maxBytes,
}) async {
  if (method != _deflated && (method != _stored || csize == null)) return null;
  final limit = math.min(csize ?? maxBytes + 4096, maxBytes + 4096);
  Stream<List<int>> data = file.openRead(start, start + limit);
  if (method == _deflated) data = data.transform(ZLibDecoder(raw: true));
  final out = BytesBuilder(copy: false);
  try {
    await for (final chunk in data) {
      if (out.length + chunk.length > maxBytes) return null;
      out.add(chunk);
    }
  } on FormatException {
    return null;
  }
  return utf8.decode(out.takeBytes(), allowMalformed: true);
}

// ──────────────── Read ────────────────

/// The central directory of the zip at [path], in archive order.
// ponytail: `archive` parses it synchronously and visits every local header,
// about a second of blocked isolate per 100k entries; a central-directory
// reader of our own is the upgrade path.
List<ZipFileHeader> readZipDirectory(String path) {
  // Without this, `archive` walks a truncated multi-gigabyte file backwards
  // a kilobyte at a time looking for the end record.
  final raf = File(path).openSync();
  try {
    final length = raf.lengthSync();
    final tail = math.min(length, zipEndRecordTail);
    raf.setPositionSync(length - tail);
    if (!zipHasEndRecord(raf.readSync(tail))) throw const CorruptZipException();
  } finally {
    raf.closeSync();
  }

  final input = InputFileStream(path);
  try {
    final directory = ZipDirectory()..read(input);
    if (directory.filePosition < 0 ||
        directory.fileHeaders.length !=
            directory.totalCentralDirectoryEntries) {
      throw const CorruptZipException();
    }
    return directory.fileHeaders;
  } on FileSystemException {
    rethrow;
  } catch (_) {
    throw const CorruptZipException();
  } finally {
    input.closeSync();
  }
}

/// Where [header]'s data starts: the local header's own name and extra
/// lengths decide, not the central directory's.
int _dataOffset(RandomAccessFile zip, ZipFileHeader header) {
  zip.setPositionSync(header.localHeaderOffset + 26);
  final lengths = zip.readSync(4);
  if (lengths.length < 4) throw const CorruptZipException();
  return header.localHeaderOffset + 30 + _u16(lengths, 0) + _u16(lengths, 2);
}

/// Streams one entry of [zip] into [target], verifying its size and CRC.
/// [headers] is an open handle on the same zip, reused across entries for
/// the local-header reads. [onBytes] gets each chunk's uncompressed length
/// and may throw to stop the extraction.
Future<void> extractZipEntry(
  File zip,
  RandomAccessFile headers,
  ZipFileHeader header,
  File target, {
  void Function(int bytes)? onBytes,
}) async {
  final method = header.compressionMethod;
  final encrypted = header.generalPurposeBitFlag & 0x01 != 0;
  if ((method != _stored && method != _deflated) || encrypted) {
    throw const CorruptZipException();
  }
  final start = _dataOffset(headers, header);
  Stream<List<int>> data = zip.openRead(start, start + header.compressedSize);
  if (method == _deflated) data = data.transform(ZLibDecoder(raw: true));

  var crc = 0;
  var size = 0;
  final out = await target.open(mode: FileMode.write);
  try {
    await for (final chunk in data) {
      crc = getCrc32(chunk, crc);
      size += chunk.length;
      // A lying header must not fill the disk before the check below.
      if (size > header.uncompressedSize) throw const CorruptZipException();
      await out.writeFrom(chunk);
      onBytes?.call(chunk.length);
    }
  } on FormatException {
    throw const CorruptZipException();
  } finally {
    await out.close();
  }
  // zlib accepts a stream cut short, so the size check is not redundant.
  if (crc != header.crc32 || size != header.uncompressedSize) {
    throw const CorruptZipException();
  }
}

// ──────────────── Write ────────────────

/// Writes a zip in the shape the Android job's `ResumableZipWriter` does
/// (the one `java.util.zip.ZipOutputStream` produces in streaming mode):
/// data descriptors, UTF-8 names, every entry DEFLATED, ZIP64 records only
/// where a field overflows. Level 0 still yields stored blocks, so already
/// compressed payload costs only the block headers, and Android's
/// sequential `ZipInputStream` (which refuses STORED entries with a data
/// descriptor) can restore the result.
///
/// The caller owns [_out]. [forceZip64] exists for tests only: it writes the
/// ZIP64 records for a small archive so that branch is exercised without
/// multi-gigabyte fixtures.
// ponytail: the CRC is computed in Dart on the calling isolate, which bounds
// throughput at roughly 100-200 MB/s; move the job to an isolate if exports
// turn out CPU-bound.
class FullBackupZipWriter {
  FullBackupZipWriter(this._out, {this.forceZip64 = false});

  final RandomAccessFile _out;
  final bool forceZip64;
  final _records = <_ZipRecord>[];

  /// Bytes written so far.
  int offset = 0;

  int get entries => _records.length;

  /// Appends one entry. [onBytes] gets each source chunk's length and may
  /// throw to stop the write.
  Future<void> add(
    String name,
    int mtimeMs,
    int level,
    Stream<List<int>> source, {
    void Function(int bytes)? onBytes,
  }) async {
    final nameBytes = utf8.encode(name);
    final time = zipDosTime(mtimeMs);
    final locOffset = offset;
    await _write(
      _ZipBytes()
        ..u32(_locSig)
        ..u16(_versionDefault)
        ..u16(_flags)
        ..u16(_deflated)
        ..u32(time)
        ..u32(0) // crc, csize, size follow in the data descriptor
        ..u32(0)
        ..u32(0)
        ..u16(nameBytes.length)
        ..u16(0)
        ..bytes(nameBytes),
    );

    var crc = 0;
    var size = 0;
    var csize = 0;
    final deflated = source
        .map((chunk) {
          crc = getCrc32(chunk, crc);
          size += chunk.length;
          onBytes?.call(chunk.length);
          return chunk;
        })
        .transform(ZLibEncoder(level: level, raw: true));
    await for (final chunk in deflated) {
      await _out.writeFrom(chunk);
      csize += chunk.length;
    }
    offset += csize;

    final descriptor = _ZipBytes()
      ..u32(_extSig)
      ..u32(crc);
    if (csize >= _magic32 || size >= _magic32) {
      descriptor
        ..u64(csize)
        ..u64(size);
    } else {
      descriptor
        ..u32(csize)
        ..u32(size);
    }
    await _write(descriptor);
    _records.add((
      name: nameBytes,
      time: time,
      crc: crc,
      csize: csize,
      size: size,
      offset: locOffset,
    ));
  }

  /// Writes the central directory and end records, then syncs the file.
  Future<void> finish() async {
    final cenStart = offset;
    final cen = _ZipBytes();
    for (final r in _records) {
      final wideCsize = forceZip64 || r.csize >= _magic32;
      final wideSize = forceZip64 || r.size >= _magic32;
      final wideOffset = forceZip64 || r.offset >= _magic32;
      final zip64Length =
          (wideCsize ? 8 : 0) + (wideSize ? 8 : 0) + (wideOffset ? 8 : 0);
      final version = zip64Length > 0 ? _versionZip64 : _versionDefault;
      cen
        ..u32(_cenSig)
        ..u16(version) // made by
        ..u16(version) // needed to extract
        ..u16(_flags)
        ..u16(_deflated)
        ..u32(r.time)
        ..u32(r.crc)
        ..u32(wideCsize ? _magic32 : r.csize)
        ..u32(wideSize ? _magic32 : r.size)
        ..u16(r.name.length)
        ..u16(zip64Length > 0 ? zip64Length + 4 : 0) // extra length
        ..u16(0) // comment length
        ..u16(0) // disk number start
        ..u16(0) // internal attributes
        ..u32(0) // external attributes
        ..u32(wideOffset ? _magic32 : r.offset)
        ..bytes(r.name);
      if (zip64Length > 0) {
        cen
          ..u16(0x0001)
          ..u16(zip64Length);
        if (wideSize) cen.u64(r.size);
        if (wideCsize) cen.u64(r.csize);
        if (wideOffset) cen.u64(r.offset);
      }
    }
    final cenLength = cen.length;
    final count = _records.length;
    final zip64 =
        forceZip64 ||
        cenLength >= _magic32 ||
        cenStart >= _magic32 ||
        count >= _magic16;
    if (zip64) {
      cen
        ..u32(0x06064b50) // ZIP64 end record
        ..u64(44)
        ..u16(_versionZip64)
        ..u16(_versionZip64)
        ..u32(0) // this disk
        ..u32(0) // disk with the central directory
        ..u64(count)
        ..u64(count)
        ..u64(cenLength)
        ..u64(cenStart)
        ..u32(0x07064b50) // ZIP64 end locator
        ..u32(0)
        ..u64(cenStart + cenLength)
        ..u32(1);
    }
    // Forced mode also masks the END fields so a reader must consult the
    // ZIP64 records, as it would for a real >4 GiB archive.
    cen
      ..u32(0x06054b50)
      ..u16(0)
      ..u16(0)
      ..u16(forceZip64 || count >= _magic16 ? _magic16 : count)
      ..u16(forceZip64 || count >= _magic16 ? _magic16 : count)
      ..u32(forceZip64 || cenLength >= _magic32 ? _magic32 : cenLength)
      ..u32(forceZip64 || cenStart >= _magic32 ? _magic32 : cenStart)
      ..u16(0); // comment length
    await _write(cen);
    await _out.flush();
  }

  Future<void> _write(_ZipBytes bytes) async {
    offset += bytes.length;
    await _out.writeFrom(bytes.take());
  }
}

/// MS-DOS date/time in local time, as `ZipEntry.setTime` would store it.
int zipDosTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  if (t.year < 1980) return (1 << 21) | (1 << 16);
  return ((t.year - 1980) << 25 |
          t.month << 21 |
          t.day << 16 |
          t.hour << 11 |
          t.minute << 5 |
          t.second >> 1) &
      _magic32;
}

typedef _ZipRecord = ({
  List<int> name,
  int time,
  int crc,
  int csize,
  int size,
  int offset,
});

/// Little-endian byte packing.
class _ZipBytes {
  final _builder = BytesBuilder(copy: false);

  int get length => _builder.length;

  void u16(int v) => _builder.add([v & 0xFF, (v >> 8) & 0xFF]);

  void u32(int v) {
    u16(v & 0xFFFF);
    u16((v >> 16) & 0xFFFF);
  }

  void u64(int v) {
    u32(v & _magic32);
    u32((v >> 32) & _magic32);
  }

  void bytes(List<int> v) => _builder.add(v);

  Uint8List take() => _builder.takeBytes();
}

int _u16(List<int> b, int at) => b[at] | b[at + 1] << 8;
int _u32(List<int> b, int at) => _u16(b, at) | _u16(b, at + 2) << 16;

const _locSig = 0x04034b50;
const _extSig = 0x08074b50;
const _cenSig = 0x02014b50;
const _magic32 = 0xFFFFFFFF;
const _magic16 = 0xFFFF;
const _versionDefault = 20;
const _versionZip64 = 45;
const _stored = 0;
const _deflated = 8;

/// Bit 3: sizes in a data descriptor; bit 11: UTF-8 names.
const _flags = 0x0808;
