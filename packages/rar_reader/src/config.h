/*
 * libarchive configuration for the RAR reader (included by
 * archive_platform.h through HAVE_CONFIG_H).
 *
 * The platform settings come from libarchive's own prebuilt configs
 * (contrib/android/config) on Android and Linux test hosts, and from
 * darwin.h on iOS and macOS. Every platform then gets the same overrides:
 * nothing links zlib, liblzma or iconv (the RAR readers fall back to
 * libarchive's own CRC32), and the current character set is always UTF-8,
 * so RAR4 Unicode names convert the same way everywhere.
 */
#ifndef MEKURU_RAR_READER_CONFIG_H
#define MEKURU_RAR_READER_CONFIG_H

#if defined(__ANDROID__)
#include "../third_party/libarchive/contrib/android/config/android.h"
/* Bionic's branch of default_iconv_charset() already returns "UTF-8". */
#else
#if defined(__APPLE__)
#include "darwin.h"
#else
#include "../third_party/libarchive/contrib/android/config/linux_host.h"
#endif
/* Declared before the macro below so its prototype is never rewritten. */
#include <langinfo.h>
/* In the C locale nl_langinfo(CODESET) is ASCII, which turns Japanese
 * names into '?'. */
#undef HAVE_NL_LANGINFO
#define HAVE_NL_LANGINFO 1
#define nl_langinfo(item) "UTF-8"
#endif

#undef HAVE_ZLIB_H
#undef HAVE_LIBZ
#undef HAVE_LIBLZMA
#undef HAVE_LZMA_H
#undef HAVE_ICONV
#undef HAVE_ICONV_H

#ifndef __LIBARCHIVE_CONFIG_H_INCLUDED
#define __LIBARCHIVE_CONFIG_H_INCLUDED 1
#endif
#ifndef HAVE_DECL_INT32_MAX
#define HAVE_DECL_INT32_MAX 1
#define HAVE_DECL_INT32_MIN 1
#define HAVE_DECL_INTMAX_MAX 1
#define HAVE_DECL_INTMAX_MIN 1
#define HAVE_DECL_UINTMAX_MAX 1
#endif

#endif
