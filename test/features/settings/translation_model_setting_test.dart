import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to Standard and remembers High quality', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(translationModelProvider),
      TranslationModelChoice.standard,
    );

    container
        .read(translationModelProvider.notifier)
        .setChoice(TranslationModelChoice.high);
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.translation_model'), 'high');

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    await reloaded
        .read(translationModelProvider.notifier)
        .loadPersistedSettings();
    expect(
      reloaded.read(translationModelProvider),
      TranslationModelChoice.high,
    );
  });

  test('backups include the setting', () {
    expect(
      SharedPreferencesAppSettingsStorage.allKeys,
      contains('app.translation_model'),
    );
  });
}
