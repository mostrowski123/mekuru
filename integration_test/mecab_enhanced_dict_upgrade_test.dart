// Regression test for the UniDic-lite startup freeze (see Serena memory
// `unidic_main_isolate_init_freeze`).
//
// The bug: enabling the enhanced-furigana dictionary made MecabService.init()
// load the ~260 MB UniDic-lite model synchronously on the main isolate, which
// froze the app for minutes under memory pressure and left word taps silently
// broken until init eventually finished.
//
// The fix's contract — exercised here on a real device — is:
//   1. init() ALWAYS brings up the small bundled IPADIC first and returns with
//      taps working, even when the enhanced dictionary is enabled + installed.
//      It must NOT block on (or switch directly to) the heavy dictionary.
//   2. The enhanced dictionary is then loaded off the main isolate and swapped
//      in afterwards.
//   3. Background isolates that pass `init(upgradeToEnhanced: false)` (e.g. the
//      OCR worker) stay on IPADIC and never load the heavy dictionary.
//
// A real UniDic-lite download is 250 MB and impractical on CI, so we stand in a
// copy of the bundled IPADIC as the "installed" enhanced dictionary. The test
// asserts the init SEQUENCING (IPADIC-first, then a background swap), which is
// the behavior that regressed — independent of the stand-in's contents.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marker file the download service checks to consider the dict installed.
/// Mirrors `EnhancedFuriganaDictDownloadService._markerFileName`.
const _installMarkerName = '.install_complete';

/// Polls [condition] until it returns true or [timeout] elapses. Returns the
/// final value of [condition]. The pump lets the background-upgrade isolate
/// complete and the swap run on the main isolate's event loop.
Future<bool> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(step);
  }
  return condition();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String enhancedDir;

  setUpAll(() async {
    // Bring IPADIC up once so its dictionary files are installed on disk; we
    // reuse them as the stand-in "enhanced" dictionary. Mecab.create only
    // needs a valid MeCab dictionary directory, which IPADIC is.
    await MecabService.instance.init(upgradeToEnhanced: false);

    final docsDir = await getApplicationDocumentsDirectory();
    // Mirrors MecabService._getDictDir(): bundled IPADIC is installed here.
    final ipadicDir = Directory(p.join(docsDir.path, 'assets', 'ipadic'));
    expect(
      ipadicDir.existsSync(),
      isTrue,
      reason: 'IPADIC should be installed on disk after init()',
    );

    // Plant the stand-in enhanced dictionary at the path the download service
    // reports, and write its install marker so isInstalled() returns true.
    enhancedDir = await EnhancedFuriganaDictDownloadService.getStorageDir();
    final dest = Directory(enhancedDir);
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    dest.createSync(recursive: true);
    for (final entity in ipadicDir.listSync().whereType<File>()) {
      entity.copySync(p.join(enhancedDir, p.basename(entity.path)));
    }
    File(p.join(enhancedDir, _installMarkerName)).writeAsStringSync('{}');

    // Opt in. shouldUse() reads SharedPreferences directly.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      EnhancedFuriganaDictDownloadService.enabledPreferenceKey,
      true,
    );
  });

  tearDownAll(() async {
    // Leave the device clean: remove the stand-in dict and the opt-in flag.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(
      EnhancedFuriganaDictDownloadService.enabledPreferenceKey,
    );
    final dest = Directory(enhancedDir);
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    await MecabService.instance.resetForTest();
  });

  setUp(() async {
    // Each case re-exercises init() from a clean MeCab state.
    await MecabService.instance.resetForTest();
  });

  test(
    'enabled + installed: init returns on IPADIC first, then swaps in the '
    'enhanced dictionary off the main isolate',
    () async {
      await MecabService.instance.init();

      // Contract 1: init must return with the lightweight IPADIC ready — NOT
      // blocked on, and NOT switched directly to, the heavy enhanced dict.
      expect(MecabService.instance.isInitialized, isTrue);
      expect(MecabService.instance.initError, isNull);
      expect(
        MecabService.instance.layout,
        MecabFeatureLayout.ipadic,
        reason: 'init() must come up on IPADIC first, never blocking on or '
            'switching straight to the enhanced dictionary',
      );

      // Taps work immediately, before any background upgrade finishes.
      expect(
        MecabService.instance.identifyWord('日本語', 0),
        isNotNull,
        reason: 'word taps must work as soon as init() returns',
      );

      // Contract 2: the enhanced dictionary is swapped in afterwards.
      final swapped = await _waitUntil(
        () => MecabService.instance.layout == MecabFeatureLayout.unidicLite,
      );
      expect(
        swapped,
        isTrue,
        reason: 'the background upgrade should swap in the enhanced dictionary',
      );

      // The swapped-in tagger is still functional for tokenization.
      expect(MecabService.instance.tokenize('日本語'), isNotEmpty);
    },
  );

  test(
    'expectedLayout predicts the enhanced dictionary and settledLayout '
    'waits for the swap',
    () async {
      await MecabService.instance.init();

      // Immediately after init the swap may or may not have landed, but the
      // session is already expected to settle on the enhanced dictionary —
      // this is what lets manga self-heal checks skip waiting for the load.
      expect(
        MecabService.instance.expectedLayout,
        MecabFeatureLayout.unidicLite,
      );

      // settledLayout must block until the upgrade finished and report the
      // dictionary tap-time lookups will actually use.
      final settled = await MecabService.instance.settledLayout();
      expect(settled, MecabFeatureLayout.unidicLite);
      expect(MecabService.instance.layout, MecabFeatureLayout.unidicLite);
    },
  );

  test(
    'upgradeToEnhanced: false stays on IPADIC even when the enhanced '
    'dictionary is enabled + installed (OCR-worker path)',
    () async {
      await MecabService.instance.init(upgradeToEnhanced: false);

      expect(MecabService.instance.isInitialized, isTrue);
      expect(MecabService.instance.layout, MecabFeatureLayout.ipadic);
      expect(MecabService.instance.identifyWord('日本語', 0), isNotNull);

      // With no upgrade in flight, both accessors report IPADIC without
      // waiting — the OCR worker records this as segmentation provenance.
      expect(MecabService.instance.expectedLayout, MecabFeatureLayout.ipadic);
      expect(
        await MecabService.instance.settledLayout(),
        MecabFeatureLayout.ipadic,
      );

      // No upgrade must fire: the layout stays IPADIC for the whole window.
      final swapped = await _waitUntil(
        () => MecabService.instance.layout == MecabFeatureLayout.unidicLite,
        timeout: const Duration(seconds: 4),
      );
      expect(
        swapped,
        isFalse,
        reason: 'background isolates opting out must never load the heavy '
            'enhanced dictionary',
      );
    },
  );
}
