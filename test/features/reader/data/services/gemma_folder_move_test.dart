import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../shared/fake_path_provider.dart';

// Its own file: GemmaTranslation works out its folder once per isolate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a model from a pre-release build moves out of Standard\'s folder',
    () async {
      final support = Directory.systemTemp.createTempSync('gemma_move_');
      addTearDown(() => support.deleteSync(recursive: true));
      PathProviderPlatform.instance = FakePathProviderPlatform(support.path);
      final old = p.join(support.path, 'translation_models', 'gemma-4-e2b');
      File(
        p.join(old, '${gemmaModelFile.name}.part'),
      ).createSync(recursive: true);
      File(p.join(old, 'INSTALLED')).createSync();

      expect(
        await GemmaTranslation.instance.status('en'),
        TranslationStatus.installed,
      );
      expect(Directory(old).existsSync(), isFalse);
      expect(
        File(
          p.join(support.path, 'gemma-4-e2b', '${gemmaModelFile.name}.part'),
        ).existsSync(),
        isTrue,
      );
    },
  );
}
