abstract final class AppLinks {
  static final Uri website = Uri.https('mekuru.matthew.moe');
  static final Uri documentation = Uri.https(
    'mekuru.matthew.moe',
    '/documentation/',
  );
  static final Uri privacyPolicy = Uri.https('mekuru.matthew.moe', '/privacy');

  /// App Store Connect app ID; same as `ASC_APP_ID` in `release-ios.yml`.
  static const appStoreId = '6814013845';
}
