import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/data/services/backup_service.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowSelfSignedKey = 'app.ocr_server_allow_self_signed';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OCR server "accept self-signed certificate"', () {
    test('is unset until saved, then round-trips', () async {
      final storage = SharedPreferencesAppSettingsStorage();
      expect(await storage.loadOcrServerAllowSelfSigned(), isNull);

      await storage.saveOcrServerAllowSelfSigned(true);
      expect(await storage.loadOcrServerAllowSelfSigned(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_allowSelfSignedKey), isTrue);

      await storage.saveOcrServerAllowSelfSigned(false);
      expect(await storage.loadOcrServerAllowSelfSigned(), isFalse);
    });

    test('is carried by JSON backups', () {
      expect(
        SharedPreferencesAppSettingsStorage.allKeys,
        contains(_allowSelfSignedKey),
      );
      expect(BackupService.appKeys, contains(_allowSelfSignedKey));
    });

    test('provider defaults to off and loads the saved value', () async {
      final defaults = ProviderContainer();
      addTearDown(defaults.dispose);
      await defaults
          .read(ocrServerAllowSelfSignedProvider.notifier)
          .loadPersistedSettings();
      expect(defaults.read(ocrServerAllowSelfSignedProvider), isFalse);

      SharedPreferences.setMockInitialValues({_allowSelfSignedKey: true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(ocrServerAllowSelfSignedProvider.notifier)
          .loadPersistedSettings();
      expect(container.read(ocrServerAllowSelfSignedProvider), isTrue);
    });

    test('provider persists a change', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(ocrServerAllowSelfSignedProvider.notifier)
          .setAllowSelfSigned(true);
      expect(container.read(ocrServerAllowSelfSignedProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_allowSelfSignedKey), isTrue);
    });
  });
}
