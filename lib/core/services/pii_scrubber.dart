import 'package:sentry_flutter/sentry_flutter.dart';

/// Scrubs user-identifying text from outgoing Sentry payloads so that book
/// file names (which users often name after the book title) never leave the
/// device inside exception messages, log bodies, attributes, or breadcrumbs.
///
/// The battery, in order: URIs, Android roots (which swallow the rest of the
/// path segment, including spaces, up to a structural delimiter), generic
/// POSIX/SAF/Windows paths, and bare filenames with book-ish extensions.
/// Over-scrubbing trailing prose is acceptable; leaking a file name is not.
final RegExp _uriPattern = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://\S+');

final RegExp _androidPathPattern = RegExp(
  r'''/(?:data/(?:user/\d+|data|app)|storage/[^/\s'"]+|sdcard|mnt/[^/\s'"]+)'''
  r'''(?:/[^'"`()\[\]:;,\n]*)?''',
);

/// Any remaining separator-joined path: POSIX, SAF pseudo-paths like
/// `/document/primary:Download/…` (`:` is in the segment class), and Windows
/// drive-letter paths (`C:` matches the leading segment).
final RegExp _genericPathPattern = RegExp(
  r'[\w.\-~+%:]*(?:[\\/][\w.\-~+%:]+)+[\\/]?',
);

/// Book-ish extensions whose bare filenames get redacted even without a path.
/// Up to three space-separated segments ("秘密の本 volume 1.cbz"). Full paths
/// are already gone by this point, so this only mops up name-only mentions.
final RegExp _bareFileNamePattern = RegExp(
  r'(?:[^\s<>]+ ){0,2}[^\s<>]+\.(?:'
  'epub|cbz|cbr|cbt|zip|rar|json|mekuru|csv|mokuro|txt|tar|gz|tgz|'
  'png|jpg|jpeg|webp|gif|avif|pdf|db|sqlite|apk|dic|bin'
  r')\b',
  caseSensitive: false,
);

const String _pathReplacement = '<path>';

/// Replaces every URI, filesystem path, and bare filename in [input].
String scrubPaths(String input) => input
    .replaceAll(_uriPattern, '<uri>')
    .replaceAll(_androidPathPattern, _pathReplacement)
    .replaceAll(_genericPathPattern, _pathReplacement)
    .replaceAll(_bareFileNamePattern, '<file>');

/// `beforeSend` hook: scrubs paths from exception values, the event message,
/// and breadcrumbs. Never throws and never drops the event — on any scrubbing
/// failure the event is sent as-is rather than lost.
SentryEvent scrubEvent(SentryEvent event, Hint hint) {
  try {
    final exceptions = event.exceptions;
    if (exceptions != null) {
      for (final exception in exceptions) {
        final value = exception.value;
        if (value != null) {
          exception.value = scrubPaths(value);
        }
      }
    }
    final message = event.message;
    if (message != null) {
      message.formatted = scrubPaths(message.formatted);
      final template = message.template;
      if (template != null) {
        message.template = scrubPaths(template);
      }
    }
    final breadcrumbs = event.breadcrumbs;
    if (breadcrumbs != null) {
      for (final breadcrumb in breadcrumbs) {
        final breadcrumbMessage = breadcrumb.message;
        if (breadcrumbMessage != null) {
          breadcrumb.message = scrubPaths(breadcrumbMessage);
        }
      }
    }
  } catch (_) {
    // Scrubbing must never cost us the event.
  }
  return event;
}

/// `beforeSendLog` hook: scrubs paths from the log body and every string
/// attribute, so no caller can leak a path through an attribute value.
/// Never throws and never drops the log.
SentryLog scrubLog(SentryLog log) {
  try {
    log.body = scrubPaths(log.body);
    for (final entry in log.attributes.entries.toList()) {
      final value = entry.value.value;
      if (value is String) {
        log.attributes[entry.key] = SentryAttribute.string(scrubPaths(value));
      }
    }
  } catch (_) {
    // Scrubbing must never cost us the log.
  }
  return log;
}
