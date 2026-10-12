// The libarchive functions RarReader uses, resolved from the library that
// hook/build.dart compiles (its assetName is this file). @Native looks each
// one up by its Dart name, hence the C names.
// ignore_for_file: non_constant_identifier_names
import 'dart:ffi';

import 'package:ffi/ffi.dart';

const archiveEof = 1;
const archiveWarn = -20;

/// AE_IFREG: a regular file (not a directory, link or device).
const aeIfreg = 0x8000;

@Native<Pointer<Void> Function()>()
external Pointer<Void> archive_read_new();

@Native<Int Function(Pointer<Void>)>()
external int archive_read_free(Pointer<Void> archive);

@Native<Int Function(Pointer<Void>)>()
external int archive_read_support_format_rar(Pointer<Void> archive);

@Native<Int Function(Pointer<Void>)>()
external int archive_read_support_format_rar5(Pointer<Void> archive);

@Native<Int Function(Pointer<Void>, Pointer<Utf8>, Size)>()
external int archive_read_open_filename(
  Pointer<Void> archive,
  Pointer<Utf8> fileName,
  int blockSize,
);

@Native<Int Function(Pointer<Void>, Pointer<Pointer<Void>>)>()
external int archive_read_next_header(
  Pointer<Void> archive,
  Pointer<Pointer<Void>> entry,
);

@Native<IntPtr Function(Pointer<Void>, Pointer<Uint8>, Size)>()
external int archive_read_data(
  Pointer<Void> archive,
  Pointer<Uint8> buffer,
  int size,
);

@Native<Int Function(Pointer<Void>)>()
external int archive_read_has_encrypted_entries(Pointer<Void> archive);

@Native<Int64 Function(Pointer<Void>, Int)>()
external int archive_filter_bytes(Pointer<Void> archive, int filter);

@Native<Pointer<Utf8> Function(Pointer<Void>)>()
external Pointer<Utf8> archive_error_string(Pointer<Void> archive);

@Native<Pointer<Utf8> Function(Pointer<Void>)>()
external Pointer<Utf8> archive_entry_pathname_utf8(Pointer<Void> entry);

@Native<Pointer<Utf8> Function(Pointer<Void>)>()
external Pointer<Utf8> archive_entry_pathname(Pointer<Void> entry);

@Native<UnsignedInt Function(Pointer<Void>)>()
external int archive_entry_filetype(Pointer<Void> entry);

@Native<Int64 Function(Pointer<Void>)>()
external int archive_entry_size(Pointer<Void> entry);

@Native<Int Function(Pointer<Void>)>()
external int archive_entry_size_is_set(Pointer<Void> entry);

@Native<Int Function(Pointer<Void>)>()
external int archive_entry_is_data_encrypted(Pointer<Void> entry);
