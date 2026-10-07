import 'package:mekuru/core/services/secret_store.dart';

const defaultOcrServerUrl = '';

/// Bearer key for a self-hosted OCR server; secure storage only.
const ocrCustomServerSecretStore = SecretStore('ocr.custom_server_bearer_key');
const legacyBuiltInOcrServerUrl =
    'https://mostrowski123--mekuru-ocr-fastapi-app.modal.run';

const mekuruOcrRepoUrl = 'https://github.com/mostrowski123/mekuru-ocr';

String normalizeOcrServerUrl(String url) {
  var normalized = url.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool isBuiltInOcrServerUrl(String url) {
  final normalized = normalizeOcrServerUrl(url);
  return normalized == normalizeOcrServerUrl(legacyBuiltInOcrServerUrl);
}

bool isUnsetOrBuiltInOcrServerUrl(String url) {
  final normalized = normalizeOcrServerUrl(url);
  return normalized.isEmpty || isBuiltInOcrServerUrl(normalized);
}

Uri? tryParseOcrServerUrl(String url) {
  final normalized = normalizeOcrServerUrl(url);
  if (normalized.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(normalized);
  final hasValidScheme =
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.hasAuthority;
  return hasValidScheme && !_hostWasEscaped(uri) ? uri : null;
}

/// `Uri` percent-encodes what a host can't hold (`<`, `>`, spaces) instead of
/// rejecting it, and dart:io then throws a FormatException on the `%` before
/// any request goes out. An IPv6 literal's `%` zone id is legitimate.
bool _hostWasEscaped(Uri uri) =>
    uri.host.contains('%') && !uri.host.contains(':');

/// What is wrong with a server URL, for the UI to put in words.
enum ServerUrlProblem {
  /// Nothing was entered.
  missing,

  /// The address holds spaces or symbols like `< >`.
  spacesOrSymbols,

  /// Not a full http:// or https:// URL.
  invalid,
}

/// What is wrong with [url] as a server URL, or null when it is usable.
ServerUrlProblem? validateOcrServerUrl(String url, {bool allowEmpty = false}) {
  final normalized = normalizeOcrServerUrl(url);
  if (normalized.isEmpty) {
    return allowEmpty ? null : ServerUrlProblem.missing;
  }

  if (tryParseOcrServerUrl(normalized) != null) {
    return null;
  }

  final parsed = Uri.tryParse(normalized);
  return parsed != null && _hostWasEscaped(parsed)
      ? ServerUrlProblem.spacesOrSymbols
      : ServerUrlProblem.invalid;
}
