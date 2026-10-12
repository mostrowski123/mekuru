# libarchive (vendored subset)

The files here are copied unchanged from the libarchive **3.8.9** release
tarball, keeping their paths in it. Only what reading RAR 4 and RAR 5 archives
from a file needs was copied: `hook/build.dart` lists the `.c` files it
compiles, and the `.h` files are the ones those include. libarchive's RAR
readers are its own BSD-licensed code; nothing here comes from RARLAB's UnRAR.

- Source: `libarchive-3.8.9.tar.xz` from
  https://github.com/libarchive/libarchive/releases/tag/v3.8.9
- SHA-256: `888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde`
- Signature: `libarchive-3.8.9.tar.xz.asc` checked with `gpg --verify` against
  key `659C84C0E23EA1FA97E0B58CC040B508D63D2B36` (Martin Matuska, the
  libarchive maintainer who published the release; the key is listed on his
  GitHub account `mmatuska`). Good signature, 2026-10-12.
- Licence: `COPYING` (BSD-2-Clause; BLAKE2 under CC0, PPMd public domain).

Copied:

- `COPYING`
- `contrib/android/config/android.h`, `contrib/android/config/linux_host.h`
  (platform settings for Android and Linux test hosts)
- `contrib/android/include/android_lf.h` (included by `archive.h` on Android)
- `libarchive/`: `archive_acl.c`, `archive_blake2s_ref.c`,
  `archive_blake2sp_ref.c`, `archive_check_magic.c`, `archive_entry.c`,
  `archive_entry_sparse.c`, `archive_entry_xattr.c`, `archive_ppmd7.c`,
  `archive_read.c`, `archive_read_open_filename.c`,
  `archive_read_support_format_rar.c`, `archive_read_support_format_rar5.c`,
  `archive_string.c`, `archive_string_sprintf.c`, `archive_time.c`,
  `archive_util.c`, `archive_virtual.c`, and the headers they include.

The settings for iOS and macOS (`../../src/darwin.h`) and the overrides every
platform shares (`../../src/config.h`) are this package's own.

To update: download the new release and its `.asc`, verify the signature,
copy the same files over, rebuild, and run `test/rar_reader_test.dart` (on
Linux or macOS) and `integration_test/comic_archive_import_test.dart`.
