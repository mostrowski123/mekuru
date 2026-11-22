import 'package:sentry_flutter/sentry_flutter.dart';

/// Scrubs user-identifying text from outgoing Sentry payloads so that book
/// file names (which users often name after the book title) never leave the
/// device inside exception messages, log bodies, attributes, or breadcrumbs.
///
/// The battery, in order: URIs, quoted names, absolute paths (which swallow
/// everything, spaces included, up to a structural delimiter), relative
/// paths, and bare filenames with book-ish extensions. Names may be in any
/// script.
/// Over-scrubbing trailing prose is acceptable; leaking a file name is not.
final RegExp _uriPattern = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://\S+');

/// A POSIX path (`/var/mobile/…`, `/storage/emulated/0/…`, SAF's
/// `/document/primary:Download/…`) or a Windows one (`C:\…`, `C:/…`), to the
/// end of the line or the first quote, bracket, `:`, `;` or `,` that is
/// followed by whitespace. So `Kiki's` and `primary:Download` stay inside,
/// and `' (OS Error` or `: No such file` end it.
final RegExp _absolutePathPattern = RegExp(
  r'''(?:(?<!\w)[A-Za-z]:[\\/]|(?<![^\s'"`(\[=:])/)[^\s<>'"`)\]:;,]'''
  r'''(?:[^\r\n<>'"`)\]:;,]|['"`)\]:;,](?![.'"`)\]:;,]*(?:\s|$)))*''',
);

/// A name in quotes, as iOS file errors give one (`The file “進撃の巨人 01”
/// couldn’t be opened`, `ファイル“…”を開けませんでした`): no path, often no
/// extension. Curly, straight, German and French quotes. Group 1 is a
/// lowercase identifier in straight quotes, such as the JSON field a
/// BackupFormatException names: it is matched only to be kept.
final RegExp _quotedNamePattern = RegExp(
  r'("[a-z][A-Za-z0-9_]*")|"[^"\r\n]+"|“[^“”\r\n]+”|'
  r'„[^„“”\r\n]+[“”]|«[^«»\r\n]+»',
);

/// A relative path (`books/進撃の巨人/page.jpg`, a SAF document ID
/// `primary:Download/…`). Group 1 is a Dart stack frame
/// (`package:mekuru/…dart:12:3`): it names code, not the user's files, so it
/// is matched only to be kept.
final RegExp _relativePathPattern = RegExp(
  r'''((?:package|dart):\S+)|'''
  r'''[^\s<>'"`()\[\],;\\/]*(?:[\\/][^\s<>'"`()\[\],;\\/]+)+[\\/]?''',
);

/// Book-ish extensions whose bare filenames get redacted even without a path.
/// Up to three space-separated segments ("秘密の本 volume 1.cbz"). Full paths
/// are already gone by this point, so this only mops up name-only mentions.
final RegExp _bareFileNamePattern = RegExp(
  r'(?:[^\s<>]+ ){0,2}[^\s<>]+\.(?:'
  'epub|cbz|cbr|cbt|zip|rar|json|mekuru|csv|mokuro|html|txt|tar|gz|tgz|'
  'png|jpg|jpeg|webp|gif|avif|bmp|tif|tiff|pdf|db|sqlite|apk|dic|bin'
  r')\b',
  caseSensitive: false,
);

const String _pathReplacement = '<path>';

/// Replaces every URI, quoted name, filesystem path, and bare filename in
/// [input].
String scrubPaths(String input) => input
    .replaceAll(_uriPattern, '<uri>')
    .replaceAllMapped(_quotedNamePattern, (m) {
      final quoted = m[0]!;
      return m[1] ?? '${quoted[0]}<file>${quoted[quoted.length - 1]}';
    })
    .replaceAllMapped(_absolutePathPattern, (m) {
      final path = m[0]!;
      final kept = path.trimRight();
      return '$_pathReplacement${path.substring(kept.length)}';
    })
    .replaceAllMapped(_relativePathPattern, (m) => m[1] ?? _pathReplacement)
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

/// SDK-attached metadata whose values the app did not author. Only these
/// exact keys are exempt from scrubbing — without the exemption the
/// bare-filename battery mangles `sentry.release`
/// (`moe.matthew.mekuru@…` → `<file>@…`). The rest of the `sentry.`
/// namespace stays covered: `sentry.message.template` and
/// `sentry.message.parameter.*` carry caller-supplied content.
const Set<String> _sdkMetadataKeys = {
  'sentry.release',
  'sentry.environment',
  'sentry.sdk.name',
  'sentry.sdk.version',
};

/// `beforeSendLog` hook: scrubs paths from the log body and every string
/// attribute, so no caller can leak a path through an attribute value.
/// Never throws and never drops the log.
SentryLog scrubLog(SentryLog log) {
  try {
    log.body = scrubPaths(log.body);
    for (final entry in log.attributes.entries.toList()) {
      if (_sdkMetadataKeys.contains(entry.key)) continue;
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
