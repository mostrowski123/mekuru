const defaultOcrServerUrl = '';
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
  return hasValidScheme ? uri : null;
}

String? validateOcrServerUrl(String url, {bool allowEmpty = false}) {
  final normalized = normalizeOcrServerUrl(url);
  if (normalized.isEmpty) {
    return allowEmpty ? null : 'Enter your server URL.';
  }

  if (tryParseOcrServerUrl(normalized) == null) {
    return 'Enter a full http:// or https:// server URL.';
  }

  return null;
}
