import 'package:sentry_flutter/sentry_flutter.dart';

/// Scrubs absolute device paths from outgoing Sentry payloads so that book
/// file names (which users often name after the book title) never leave the
/// device inside exception messages, log bodies, or breadcrumbs.
///
/// Matches Android app-private and shared-storage roots and swallows the rest
/// of the path segment, including spaces, up to a structural delimiter. Over-
/// scrubbing trailing prose is acceptable; leaking a file name is not.
final RegExp _androidPathPattern = RegExp(
  r'''/(?:data/(?:user/\d+|data|app)|storage/[^/\s'"]+|sdcard|mnt/[^/\s'"]+)'''
  r'''(?:/[^'"`()\[\]:;,\n]*)?''',
);

const String _pathReplacement = '<path>';

/// Replaces every Android filesystem path in [input] with `<path>`.
String scrubPaths(String input) =>
    input.replaceAll(_androidPathPattern, _pathReplacement);

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

/// `beforeSendLog` hook: scrubs paths from the log body. Never throws and
/// never drops the log.
SentryLog scrubLog(SentryLog log) {
  try {
    log.body = scrubPaths(log.body);
  } catch (_) {
    // Scrubbing must never cost us the log.
  }
  return log;
}
