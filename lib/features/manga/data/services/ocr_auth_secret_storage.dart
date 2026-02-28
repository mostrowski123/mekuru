import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OcrAuthSecretStorage {
  static const _customServerBearerKeyKey = 'ocr.custom_server_bearer_key';
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> loadCustomServerBearerKey() async {
    final value = await _secureStorage.read(key: _customServerBearerKeyKey);
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveCustomServerBearerKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await clearCustomServerBearerKey();
      return;
    }

    await _secureStorage.write(key: _customServerBearerKeyKey, value: trimmed);
  }

  Future<void> clearCustomServerBearerKey() {
    return _secureStorage.delete(key: _customServerBearerKeyKey);
  }
}
