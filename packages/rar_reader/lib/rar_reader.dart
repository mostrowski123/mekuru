/// Reads RAR 4 and RAR 5 archives through libarchive's RAR readers.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/libarchive_bindings.dart';

/// The archive can't be read: damaged, truncated, or using a RAR feature
/// libarchive doesn't support (multi-volume, for example).
class RarException extends FormatException {
  const RarException(super.message);
}

/// The archive's file list, or the entry being read, is password-protected.
class RarEncryptedException extends RarException {
  const RarEncryptedException(super.message);
}

/// A solid archive made by RAR 4 or older. libarchive stops at its second
/// file; RAR 5 solid archives read fine.
class RarSolidUnsupportedException extends RarException {
  const RarSolidUnsupportedException(super.message);
}

/// An entry returned by [RarReader.nextEntry].
class RarEntry {
  const RarEntry({
    required this.name,
    required this.isFile,
    required this.isEncrypted,
  });

  /// Path inside the archive, with '/' separators.
  final String name;

  /// A regular file, not a directory or a link.
  final bool isFile;

  /// The entry's data is encrypted; [RarReader.readEntry] would throw.
  final bool isEncrypted;
}

/// Reads a RAR archive from the first entry to the last: call [nextEntry],
/// then [readEntry] if the entry's data is wanted, before moving on. A solid
/// archive decompresses as one stream, so there is no going back. Every call
/// blocks the calling isolate. Call [close] when done.
class RarReader {
  RarReader._(this._archive);

  /// The largest entry [readEntry] returns: the archive is untrusted input.
  static const _maxEntryBytes = 256 * 1024 * 1024;

  static const _chunkBytes = 1 << 20;
  static const _signature = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07];

  final Pointer<Void> _archive;
  final Pointer<Pointer<Void>> _entry = calloc<Pointer<Void>>();
  final Pointer<Uint8> _chunk = malloc<Uint8>(_chunkBytes);
  RarEntry? _current;

  /// The current entry's size as its header gives it, or null if unknown.
  int? _currentSize;
  bool _closed = false;

  /// True when [head] starts with the RAR 4 or RAR 5 signature.
  static bool isRar(List<int> head) {
    if (head.length < _signature.length) return false;
    for (var i = 0; i < _signature.length; i++) {
      if (head[i] != _signature[i]) return false;
    }
    return true;
  }

  /// Opens the archive at [path]. Throws [RarSolidUnsupportedException] for
  /// a solid RAR 4 archive, [RarException] when libarchive can't open it.
  factory RarReader.open(String path) {
    _rejectSolidRar4(path);
    final archive = archive_read_new();
    if (archive == nullptr) throw const RarException('Out of memory');
    archive_read_support_format_rar(archive);
    archive_read_support_format_rar5(archive);
    final opened = using(
      (arena) => archive_read_open_filename(
        archive,
        path.toNativeUtf8(allocator: arena),
        65536,
      ),
    );
    if (opened < archiveWarn) {
      final message = _errorMessage(archive);
      archive_read_free(archive);
      throw RarException(message);
    }
    return RarReader._(archive);
  }

  /// The next entry, or null at the end of the archive.
  RarEntry? nextEntry() {
    _checkOpen();
    final result = archive_read_next_header(_archive, _entry);
    if (result == archiveEof) return _current = null;
    if (result < archiveWarn) {
      final message = _errorMessage(_archive);
      // Encrypted headers fail here, before any entry is returned.
      throw archive_read_has_encrypted_entries(_archive) == 1
          ? RarEncryptedException(message)
          : RarException(message);
    }
    final entry = _entry.value;
    final utf8Name = archive_entry_pathname_utf8(entry);
    _currentSize = archive_entry_size_is_set(entry) != 0
        ? archive_entry_size(entry)
        : null;
    return _current = RarEntry(
      // shortcut: names libarchive can't convert to UTF-8 (Shift_JIS names
      // in old RAR 4 archives) decode lossily, as Shift_JIS ZIP names do.
      // Decode them as CP932 if page order ever depends on them.
      name: utf8Name != nullptr
          ? utf8Name.toDartString()
          : _cString(archive_entry_pathname(entry)),
      // AE_IFMT mask: mode_t is 16 bits on Darwin.
      isFile: archive_entry_filetype(entry) & 0xF000 == aeIfreg,
      isEncrypted: archive_entry_is_data_encrypted(entry) != 0,
    );
  }

  /// All data of the entry [nextEntry] last returned.
  Uint8List readEntry() {
    _checkOpen();
    final entry = _current;
    if (entry == null) throw StateError('No current entry');
    if (entry.isEncrypted) {
      throw RarEncryptedException('${entry.name} is encrypted');
    }
    final tooLarge = RarException(
      '${entry.name} is larger than $_maxEntryBytes bytes',
    );
    final size = _currentSize;
    if (size != null && size > _maxEntryBytes) throw tooLarge;
    // Sized from the header, so a page is copied once; grows if the header
    // understates the data.
    var data = Uint8List(size ?? _chunkBytes);
    var length = 0;
    while (true) {
      final read = archive_read_data(_archive, _chunk, _chunkBytes);
      if (read == 0) break;
      if (read < 0) throw RarException(_errorMessage(_archive));
      final end = length + read;
      if (end > data.length) {
        if (end > _maxEntryBytes) throw tooLarge;
        data = Uint8List(min(max(data.length * 2, end), _maxEntryBytes))
          ..setRange(0, length, data);
      }
      data.setRange(length, end, _chunk.asTypedList(read));
      length = end;
    }
    return length == data.length ? data : data.sublist(0, length);
  }

  /// Bytes of the archive file consumed so far, for progress.
  int get bytesConsumed {
    _checkOpen();
    return archive_filter_bytes(_archive, -1);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    archive_read_free(_archive);
    calloc.free(_entry);
    malloc.free(_chunk);
  }

  void _checkOpen() {
    if (_closed) throw StateError('RarReader is closed');
  }

  /// libarchive reads a solid RAR 4 archive's first file, then fails. The
  /// main header right after the 7-byte RAR 4 signature says whether the
  /// archive is solid (MHD_SOLID), so reject it before any page is written.
  static void _rejectSolidRar4(String path) {
    final file = File(path).openSync();
    try {
      final head = file.readSync(12);
      if (head.length == 12 &&
          isRar(head) &&
          head[6] == 0x00 && // RAR 4 (RAR 5 continues 0x01 0x00)
          head[9] == 0x73 && // main archive header
          head[10] & 0x08 != 0) {
        throw const RarSolidUnsupportedException('Solid RAR 4 archive');
      }
    } finally {
      file.closeSync();
    }
  }

  static String _errorMessage(Pointer<Void> archive) {
    final message = archive_error_string(archive);
    return message == nullptr ? 'Unreadable RAR archive' : _cString(message);
  }

  /// Unlike toDartString(), doesn't throw on bytes that aren't UTF-8.
  static String _cString(Pointer<Utf8> string) => string == nullptr
      ? ''
      : utf8.decode(
          string.cast<Uint8>().asTypedList(string.length),
          allowMalformed: true,
        );
}
