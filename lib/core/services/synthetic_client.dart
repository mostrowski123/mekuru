/// Detection for telemetry that comes from something other than a person
/// reading a book — emulators, cloud device farms, and store-scraping bots.
///
/// Mekuru ships on the Play Store *and* as a GitHub APK, so sideloaded
/// installs are a real audience and must keep reporting. This filter targets
/// synthetic clients only.
///
/// Deliberately NOT used as signals:
///
/// - `test-keys` / `userdebug` builds. LineageOS and other self-signed ROMs
///   ship these, and those users are exactly the GitHub sideload audience.
/// - x86 / x86_64 ABIs. ChromeOS runs Android apps on real x86 hardware.
///
/// Both would trade a little bot noise for real users' data, which is the
/// wrong trade. The signals below are emulator kernels and AOSP build
/// identities that no retail device reports.
library;

/// Emulator and hypervisor kernel names. No retail Android device ships these.
const Set<String> _syntheticHardware = {
  'goldfish', // Android emulator (legacy)
  'ranchu', // Android emulator (current)
  'cutf_cvm', // Cuttlefish, used by cloud device farms
  'cutf', // Cuttlefish (older naming)
  'gce_x86', // Google Compute Engine Android
  'vbox86', // Genymotion / VirtualBox
  'vbox', // VirtualBox
};

/// Substrings that only appear in AOSP/SDK build identities.
const List<String> _syntheticBuildMarkers = [
  'sdk_', // sdk_gphone*, sdk_google*, sdk_phone*
  'sdk built for',
  'aosp_cf_', // Cuttlefish
  'emulator',
  'cuttlefish',
  'vbox86',
  'genymotion',
];

/// Whether these Android build properties describe an emulator, a cloud
/// device farm, or another automated client rather than a real user's phone.
///
/// Missing or empty properties are treated as real: dropping a genuine user's
/// telemetry is worse than keeping a little noise.
bool isSyntheticAndroidClient({
  required bool isPhysicalDevice,
  required String fingerprint,
  required String hardware,
  required String product,
  required String model,
}) {
  if (!isPhysicalDevice) return true;

  if (_syntheticHardware.contains(hardware.trim().toLowerCase())) return true;

  final normalizedFingerprint = fingerprint.trim().toLowerCase();
  if (normalizedFingerprint.startsWith('generic') ||
      normalizedFingerprint.startsWith('unknown')) {
    return true;
  }

  // A real device's fingerprint embeds its product and model, but OEMs are
  // inconsistent enough that it is worth scanning all three.
  return [normalizedFingerprint, product, model]
      .map((property) => property.trim().toLowerCase())
      .any((property) => _syntheticBuildMarkers.any(property.contains));
}
