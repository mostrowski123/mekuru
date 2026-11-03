abstract final class AppLinks {
  static final Uri website = Uri.https('mekuru.matthew.moe');
  static final Uri documentation = Uri.https(
    'mekuru.matthew.moe',
    '/documentation/',
  );
  static final Uri privacyPolicy = Uri.https('mekuru.matthew.moe', '/privacy');

  /// Where word audio is hosted. `v1` is one voice: cached clips never change,
  /// so another voice gets a new path. The define points a local test build
  /// at a local copy.
  static const wordAudioBase = String.fromEnvironment(
    'WORD_AUDIO_BASE',
    defaultValue: 'https://mekuru-audio.matthew.moe/v1',
  );

  /// App Store Connect app ID; same as `ASC_APP_ID` in `release-ios.yml`.
  static const appStoreId = '6814013845';
}
