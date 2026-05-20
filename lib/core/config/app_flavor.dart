/// True when the app is built with `--dart-define=PARALLEL_BUILD=true`,
/// producing the side-by-side installable APK with package id
/// `moe.matthew.mekuru.parallel`. Defaults to `false` for the main flavor.
const bool kIsParallelBuild = bool.fromEnvironment(
  'PARALLEL_BUILD',
  defaultValue: false,
);
