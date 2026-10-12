// Compiles the libarchive files vendored in third_party/libarchive (only
// what reading RAR 4 and RAR 5 from a file needs, see its README.md) into
// one C library. src/config.h picks the platform settings.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _libarchiveSources = [
  'archive_acl.c',
  'archive_blake2s_ref.c',
  'archive_blake2sp_ref.c',
  'archive_check_magic.c',
  'archive_entry.c',
  'archive_entry_sparse.c',
  'archive_entry_xattr.c',
  'archive_ppmd7.c',
  'archive_read.c',
  'archive_read_open_filename.c',
  'archive_read_support_format_rar.c',
  'archive_read_support_format_rar5.c',
  'archive_string.c',
  'archive_string_sprintf.c',
  'archive_time.c',
  'archive_util.c',
  'archive_virtual.c',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    // No Windows config was vendored. The only Windows build is `flutter
    // test` on a Windows host, where the RAR tests are skipped.
    if (os == OS.windows) return;

    await CBuilder.library(
      name: 'rar_reader',
      assetName: 'src/libarchive_bindings.dart',
      language: Language.c,
      sources: [
        for (final file in _libarchiveSources)
          'third_party/libarchive/libarchive/$file',
      ],
      includes: [
        'src',
        'third_party/libarchive/libarchive',
        if (os == OS.android) 'third_party/libarchive/contrib/android/include',
      ],
      defines: {'HAVE_CONFIG_H': null},
      // A source file missing from the list above fails the build instead
      // of the first archive opened. Apple's linker already does this.
      flags: [if (os == OS.android || os == OS.linux) '-Wl,--no-undefined'],
    ).run(input: input, output: output);
  });
}
