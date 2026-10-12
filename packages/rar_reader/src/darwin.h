/*
 * libarchive platform settings for iOS and macOS, for the files vendored
 * in third_party/libarchive only (reading RAR archives from a file).
 * Written for this package after contrib/android/config/android.h; with
 * config.h, covers every HAVE_ / HAVE_DECL_ macro those files test.
 * config.h applies the overrides shared with the other platforms after
 * including this.
 */
#ifndef MEKURU_RAR_READER_DARWIN_H
#define MEKURU_RAR_READER_DARWIN_H

/* config.h adds __LIBARCHIVE_CONFIG_H_INCLUDED and the INT32 / INTMAX /
 * UINTMAX declarations every platform shares. */
#define HAVE_DECL_INT64_MAX 1
#define HAVE_DECL_INT64_MIN 1
#define HAVE_DECL_SIZE_MAX 1
#define HAVE_DECL_SSIZE_MAX 1
#define HAVE_DECL_UINT32_MAX 1
#define HAVE_DECL_UINT64_MAX 1

#define HAVE_EILSEQ 1
#define HAVE_ERRNO_H 1
#define HAVE_FCHMOD 1
#define HAVE_FCHOWN 1
#define HAVE_FCNTL_H 1
#define HAVE_GETEGID 1
#define HAVE_GETEUID 1
#define HAVE_INTTYPES_H 1
#define HAVE_LANGINFO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALTIME_R 1
#define HAVE_MBRTOWC 1
#define HAVE_MKSTEMP 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCRTOMB 1
#define HAVE_WCSCPY 1
#define HAVE_WCSLEN 1
#define HAVE_WCTOMB 1
#define HAVE_WMEMCMP 1
#define HAVE_WMEMCPY 1
#define HAVE_WMEMMOVE 1

#endif
