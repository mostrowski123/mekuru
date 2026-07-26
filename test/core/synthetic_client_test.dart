import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/synthetic_client.dart';

/// A stock, retail Pixel — the baseline every case below varies from.
bool check({
  bool isPhysicalDevice = true,
  String fingerprint = 'google/shiba/shiba:14/UQ1A.240205.004/11269751:user/release-keys',
  String hardware = 'zuma',
  String product = 'shiba',
  String model = 'Pixel 8',
}) => isSyntheticAndroidClient(
  isPhysicalDevice: isPhysicalDevice,
  fingerprint: fingerprint,
  hardware: hardware,
  product: product,
  model: model,
);

void main() {
  group('flags synthetic clients', () {
    test('Android Studio emulator', () {
      expect(
        check(
          fingerprint:
              'google/sdk_gphone64_arm64/emu64a:14/UE1A.230829.036/11228894:userdebug/dev-keys',
          hardware: 'ranchu',
          product: 'sdk_gphone64_arm64',
          model: 'sdk_gphone64_arm64',
        ),
        isTrue,
      );
    });

    test('legacy goldfish emulator', () {
      expect(check(hardware: 'goldfish', product: 'sdk'), isTrue);
    });

    test('Cuttlefish / cloud device farm', () {
      expect(
        check(hardware: 'cutf_cvm', product: 'aosp_cf_x86_64_phone'),
        isTrue,
      );
    });

    test('Genymotion / VirtualBox', () {
      expect(check(hardware: 'vbox86', product: 'vbox86p'), isTrue);
    });

    test('generic AOSP fingerprint', () {
      expect(
        check(fingerprint: 'generic/sdk/generic:12/SP2A.220505.008/eng:eng'),
        isTrue,
      );
    });

    test('"Android SDK built for" model', () {
      expect(check(model: 'Android SDK built for arm64'), isTrue);
    });

    test('platform reports a non-physical device', () {
      expect(check(isPhysicalDevice: false), isTrue);
    });

    test('matching ignores case', () {
      expect(check(hardware: 'RANCHU'), isTrue);
      expect(check(product: 'SDK_GPHONE64_ARM64'), isTrue);
    });
  });

  group('keeps real users', () {
    test('retail Pixel on the Play Store', () {
      expect(check(), isFalse);
    });

    test('retail Samsung', () {
      expect(
        check(
          fingerprint:
              'samsung/e1qksx/e1q:14/UP1A.231005.007/S921NKSU1AXCE:user/release-keys',
          hardware: 'qcom',
          product: 'e1qksx',
          model: 'SM-S921N',
        ),
        isFalse,
      );
    });

    test('custom ROM on test-keys — a sideload audience, not a bot', () {
      // LineageOS and other self-signed ROMs ship test-keys and userdebug
      // builds. Those users install from GitHub, so test-keys alone must
      // never be treated as synthetic.
      expect(
        check(
          fingerprint:
              'google/sunfish/sunfish:13/TQ3A.230805.001/eng.root.20230915:userdebug/test-keys',
          hardware: 'sunfish',
          product: 'lineage_sunfish',
          model: 'Pixel 4a',
        ),
        isFalse,
      );
    });

    test('ChromeOS running Android apps on x86_64', () {
      // Real hardware on an x86 ABI. Filtering on x86 would drop these users.
      expect(
        check(
          fingerprint: 'google/hatch/hatch_cheets:11/R110-15278.0.0/1:user/release-keys',
          hardware: 'hatch_cheets',
          product: 'hatch_cheets',
          model: 'kohaku',
        ),
        isFalse,
      );
    });

    test('an Onyx Boox e-reader', () {
      // Seen in production telemetry — an unusual device, but a real reader.
      expect(
        check(hardware: 'qcom', product: 'Go103_2Lumi', model: 'Go103_2Lumi'),
        isFalse,
      );
    });

    test('empty build properties are not treated as synthetic', () {
      // Missing platform data must not silently discard a real user's data.
      expect(
        check(fingerprint: '', hardware: '', product: '', model: ''),
        isFalse,
      );
    });
  });
}
