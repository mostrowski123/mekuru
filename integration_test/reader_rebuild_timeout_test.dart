// A viewer rebuilt for a new reading mode has the same load timeout as the
// first one: when its page's `loaded` call never reaches Dart, the reader
// shows its error screen instead of a spinner that never ends.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

import 'shared/scroll_view_fixture.dart' show openReader, writeScrollViewEpub;
import 'test_helpers.dart';

const _title = '再構築タイムアウト';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_rebuild_timeout_');
    await cleanupAppBooksDir();
  });

  tearDown(() async {
    CustomEpubViewer.debugLoadedDelay = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await cleanupAppBooksDir();
  });

  testWidgets('a rebuilt viewer that never shows the book times out', (
    tester,
  ) async {
    final l10n = await loadExpectedL10n();
    await openReader(
      tester,
      await writeScrollViewEpub(tempDir, title: _title, vertical: true),
      _title,
      settings: const ReaderSettings(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CustomEpubViewer)),
    );

    // Past the reader's 15 s load timeout: the call is as good as lost.
    CustomEpubViewer.debugLoadedDelay = const Duration(minutes: 2);
    container.read(readerSettingsProvider.notifier).setScrollView(true);

    await pumpUntilVisible(
      tester,
      find.text(l10n.readerLoadTimeout),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(l10n.commonRetry), findsOneWidget);
  });
}
