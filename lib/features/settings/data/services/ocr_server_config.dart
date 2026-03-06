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
