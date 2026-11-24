/// True when the app is built with `--dart-define=PARALLEL_BUILD=true`,
/// producing the side-by-side installable APK with package id
/// `moe.matthew.mekuru.parallel`. Defaults to `false` for the main flavor.
const bool kIsParallelBuild = bool.fromEnvironment(
  'PARALLEL_BUILD',
  defaultValue: false,
);

/// True only in builds made by the release workflows (`build-release.yml`,
/// `release-ios.yml`), which pass `--dart-define=OFFICIAL_BUILD=true`. Local
/// builds and CI test builds leave it false, so they never report to
/// Firebase Analytics.
const bool kIsOfficialBuild = bool.fromEnvironment('OFFICIAL_BUILD');
