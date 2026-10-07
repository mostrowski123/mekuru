import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Code built into Mekuru's native libraries and the translation engine's
/// WebAssembly, which Flutter's package license list doesn't know about:
/// libavif (AVIF pages on Android 7-11) and what Mozilla's Bergamot engine
/// compiles in. Shown on the Open Source Licenses page, by package name.
const thirdPartyLicenses = {
  'libavif': 'assets/licenses/libavif.txt',
  'dav1d': 'assets/licenses/dav1d.txt',
  'libyuv': 'assets/licenses/libyuv.txt',
  'Firefox Translations (Bergamot)': 'assets/translate/LICENSE.txt',
  'Marian NMT': 'assets/licenses/marian.txt',
  'intgemm': 'assets/licenses/intgemm.txt',
  'SentencePiece': 'assets/licenses/apache-2.0.txt',
  'Protocol Buffers': 'assets/licenses/protobuf.txt',
  'Darts-clone': 'assets/licenses/darts-clone.txt',
  'Abseil': 'assets/licenses/apache-2.0.txt',
  'esaxx': 'assets/licenses/esaxx.txt',
  'ONNX.js': 'assets/licenses/onnxjs.txt',
  // Eigen, which ONNX.js brings, is MPL 2.0 like the engine itself.
  'Eigen': 'assets/translate/LICENSE.txt',
  'cnpy': 'assets/licenses/cnpy.txt',
  'phf': 'assets/licenses/phf.txt',
  'spdlog': 'assets/licenses/spdlog.txt',
  'fmt': 'assets/licenses/fmt.txt',
  'yaml-cpp': 'assets/licenses/yaml-cpp.txt',
  'CLI11': 'assets/licenses/cli11.txt',
  'Pathie': 'assets/licenses/pathie-cpp.txt',
  'umHalf': 'assets/licenses/umhalf.txt',
};

/// Adds [thirdPartyLicenses] to [LicenseRegistry]. Once per process.
void registerThirdPartyLicenses() =>
    LicenseRegistry.addLicense(thirdPartyLicenseEntries);

/// The [thirdPartyLicenses] as license page entries.
Stream<LicenseEntry> thirdPartyLicenseEntries() async* {
  for (final MapEntry(key: package, value: asset)
      in thirdPartyLicenses.entries) {
    yield LicenseEntryWithLineBreaks([
      package,
    ], await rootBundle.loadString(asset, cache: false));
  }
}
